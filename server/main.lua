local ESX = exports['es_extended']:getSharedObject()

local RESOURCE_NAME = GetCurrentResourceName()
local DATA_FILE = 'data/stashes.json'

local stashes = {}
local registered = {}

local function sanitizeId(value)
    if type(value) ~= 'string' then
        value = tostring(value or '')
    end

    value = value:lower():gsub('%s+', '_'):gsub('[^%w_%-]', '')

    if value == '' then
        return nil
    end

    return value
end

local function trim(value)
    if type(value) ~= 'string' then return '' end
    return value:match('^%s*(.-)%s*$')
end

local function toInteger(value, fallback, minValue, maxValue)
    local num = tonumber(value)
    if not num then
        return fallback
    end

    num = math.floor(num)

    if minValue and num < minValue then
        num = minValue
    end

    if maxValue and num > maxValue then
        num = maxValue
    end

    return num
end

local function getGroups(job, jobGrade)
    if not job or job == '' then return nil end
    return { [job] = toInteger(jobGrade, 0, 0, 100) }
end

local function canManage(source)
    if source == 0 then
        return true
    end

    local xPlayer = ESX.GetPlayerFromId(source)
    local group

    if xPlayer then
        if type(xPlayer.getGroup) == 'function' then
            group = xPlayer.getGroup()
        end

        if not group and type(xPlayer.get) == 'function' then
            group = xPlayer.get('group')
        end

        if not group then
            group = xPlayer.group
        end
    end

    if type(group) == 'string' and type(Config.AdminGroups) == 'table' then
        for i = 1, #Config.AdminGroups do
            if Config.AdminGroups[i] == group then
                return true
            end
        end
    end

    if type(Config.AdminAce) == 'string' and Config.AdminAce ~= '' then
        return IsPlayerAceAllowed(source, Config.AdminAce)
    end

    return false
end

local function normalizeCoords(coords)
    if type(coords) ~= 'table' then return nil end

    local x = tonumber(coords.x)
    local y = tonumber(coords.y)
    local z = tonumber(coords.z)

    if not x or not y or not z then
        return nil
    end

    return { x = x + 0.0, y = y + 0.0, z = z + 0.0 }
end

local function saveStashes()
    local encoded = json.encode(stashes)
    SaveResourceFile(RESOURCE_NAME, DATA_FILE, encoded, -1)
end

local function findStashIndexById(id)
    for i = 1, #stashes do
        if stashes[i].id == id then
            return i
        end
    end

    return nil
end

local function registerPublicStash(stash)
    local stashId = stash.id
    if registered[stashId] then return end

    exports.ox_inventory:RegisterStash(
        stashId,
        stash.label,
        stash.slots or Config.DefaultSlots,
        stash.weight or Config.DefaultWeight,
        false,
        getGroups(stash.job, stash.jobGrade),
        stash.coords
    )

    registered[stashId] = true
end

local function loadStashes()
    local raw = LoadResourceFile(RESOURCE_NAME, DATA_FILE)

    if not raw or raw == '' then
        stashes = {}
        saveStashes()
        return
    end

    local decoded = json.decode(raw)
    if type(decoded) ~= 'table' then
        stashes = {}
        saveStashes()
        return
    end

    local parsed = {}

    for i = 1, #decoded do
        local entry = decoded[i]

        local id = sanitizeId(trim(entry.id or ''))
        local label = trim(entry.label or '')
        local coords = normalizeCoords(entry.coords)
        local job = trim(entry.job or '')

        if id and label ~= '' and coords then
            parsed[#parsed + 1] = {
                id = id,
                label = label,
                job = job,
                jobGrade = toInteger(entry.jobGrade, 0, 0, 100),
                private = entry.private == true,
                slots = toInteger(entry.slots, Config.DefaultSlots, 1, 500),
                weight = toInteger(entry.weight, Config.DefaultWeight, 1000, 5000000),
                coords = coords
            }
        end
    end

    stashes = parsed
end

local function registerStashes()
    registered = {}

    for i = 1, #stashes do
        if not stashes[i].private then
            registerPublicStash(stashes[i])
        end
    end
end

local function getCharacterKey(xPlayer)
    local charId

    if type(xPlayer.get) == 'function' then
        charId = xPlayer.get('charid') or xPlayer.get('characterId')
    end

    if not charId then
        charId = xPlayer.charid or xPlayer.characterId
    end

    if charId then
        return tostring(charId)
    end

    local identifier = xPlayer.identifier
    if type(identifier) == 'string' then
        local parsedChar = identifier:match('^(char%d+):')
        return parsedChar or identifier
    end

    return tostring(xPlayer.source)
end

local function getStashById(id)
    local index = findStashIndexById(id)
    if not index then return nil end

    return stashes[index], index
end

local function broadcastSync()
    TriggerClientEvent('stashcreator:client:sync', -1, stashes)
end

lib.callback.register('stashcreator:server:getBootstrap', function(source)
    return {
        canManage = canManage(source),
        stashes = stashes
    }
end)

lib.callback.register('stashcreator:server:createStash', function(source, payload)
    if not canManage(source) then
        return { ok = false, message = 'Nemas opravneni vytvaret stashe.' }
    end

    if type(payload) ~= 'table' then
        return { ok = false, message = 'Neplatna data.' }
    end

    local label = trim(payload.label or '')
    local id = sanitizeId(trim(payload.id or ''))
    local job = trim(payload.job or '')
    local jobGrade = toInteger(payload.jobGrade, 0, 0, 100)
    local slots = toInteger(payload.slots, Config.DefaultSlots, 1, 500)
    local weight = toInteger(payload.weight, Config.DefaultWeight, 1000, 5000000)
    local private = payload.private == true
    local coords = normalizeCoords(payload.coords)

    if label == '' then
        return { ok = false, message = 'Label je povinny.' }
    end

    if not id then
        return { ok = false, message = 'ID je neplatne.' }
    end

    if not coords then
        return { ok = false, message = 'Pozice je neplatna.' }
    end

    if findStashIndexById(id) then
        return { ok = false, message = 'Stash s timto ID uz existuje.' }
    end

    local stash = {
        id = id,
        label = label,
        job = job,
        jobGrade = job == '' and 0 or jobGrade,
        private = private,
        slots = slots,
        weight = weight,
        coords = coords
    }

    stashes[#stashes + 1] = stash
    saveStashes()

    if not stash.private then
        registerPublicStash(stash)
    end

    broadcastSync()

    return {
        ok = true,
        message = ('Stash %s vytvoren na tvoji pozici.'):format(stash.id)
    }
end)

lib.callback.register('stashcreator:server:updateStash', function(source, payload)
    if not canManage(source) then
        return { ok = false, message = 'Nemas opravneni upravovat stashe.' }
    end

    if type(payload) ~= 'table' then
        return { ok = false, message = 'Neplatna data.' }
    end

    local oldId = sanitizeId(trim(payload.oldId or ''))
    local label = trim(payload.label or '')
    local newId = sanitizeId(trim(payload.id or ''))
    local job = trim(payload.job or '')
    local jobGrade = toInteger(payload.jobGrade, 0, 0, 100)
    local slots = toInteger(payload.slots, Config.DefaultSlots, 1, 500)
    local weight = toInteger(payload.weight, Config.DefaultWeight, 1000, 5000000)
    local private = payload.private == true
    local coords = normalizeCoords(payload.coords)

    if not oldId then
        return { ok = false, message = 'Neplatne puvodni ID.' }
    end

    local stash, index = getStashById(oldId)
    if not stash or not index then
        return { ok = false, message = 'Stash nebyl nalezen.' }
    end

    if label == '' then
        return { ok = false, message = 'Label je povinny.' }
    end

    if not newId then
        return { ok = false, message = 'Nove ID je neplatne.' }
    end

    if not coords then
        return { ok = false, message = 'Pozice je neplatna.' }
    end

    if newId ~= oldId and findStashIndexById(newId) then
        return { ok = false, message = 'Nove ID uz pouziva jiny stash.' }
    end

    stashes[index] = {
        id = newId,
        label = label,
        job = job,
        jobGrade = job == '' and 0 or jobGrade,
        private = private,
        slots = slots,
        weight = weight,
        coords = coords
    }

    saveStashes()
    registerStashes()
    broadcastSync()

    local message = 'Stash byl upraven.'
    if oldId ~= newId then
        message = message .. ' Zmena ID vytvori novy inventory namespace v ox_inventory.'
    end

    return {
        ok = true,
        message = message
    }
end)

lib.callback.register('stashcreator:server:openStash', function(source, stashId)
    local id = sanitizeId(trim(stashId or ''))
    if not id then
        return { ok = false, message = 'Neplatne stash ID.' }
    end

    local stash = getStashById(id)
    if not stash then
        return { ok = false, message = 'Stash nebyl nalezen.' }
    end

    local finalId = stash.id

    if stash.private then
        local xPlayer = ESX.GetPlayerFromId(source)
        if not xPlayer then
            return { ok = false, message = 'Hrac nebyl nalezen.' }
        end

        local charKey = sanitizeId(getCharacterKey(xPlayer))
        if not charKey then
            return { ok = false, message = 'Nelze zjistit charid.' }
        end

        finalId = ('%s__%s'):format(stash.id, charKey)

        if not registered[finalId] then
            exports.ox_inventory:RegisterStash(
                finalId,
                stash.label,
                stash.slots or Config.DefaultSlots,
                stash.weight or Config.DefaultWeight,
                false,
                getGroups(stash.job, stash.jobGrade),
                stash.coords
            )

            registered[finalId] = true
        end
    else
        registerPublicStash(stash)
    end

    TriggerClientEvent('ox_inventory:openInventory', source, 'stash', finalId)

    return {
        ok = true,
        stashId = finalId
    }
end)

AddEventHandler('onResourceStart', function(resourceName)
    if resourceName ~= RESOURCE_NAME then return end

    loadStashes()
    registerStashes()
end)
