local stashes = {}
local zoneIds = {}
local canManage = false

local function notify(description, nType)
    lib.notify({
        title = 'Stash Creator',
        description = description,
        type = nType or 'inform',
        position = Config.Notify.Position
    })
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

local function removeAllZones()
    for _, zoneId in pairs(zoneIds) do
        exports.ox_target:removeZone(zoneId)
    end

    zoneIds = {}
end

local function buildStashDescription(stash)
    local suffix = stash.private and ' | soukromy' or ''
    local job = stash.job and stash.job ~= '' and (' | job: ' .. stash.job .. ' (' .. tostring(stash.jobGrade or 0) .. '+)') or ''
    local slots = tonumber(stash.slots) or Config.DefaultSlots
    local weight = tonumber(stash.weight) or Config.DefaultWeight

    return ('ID: %s%s%s | slots: %s | weight: %s'):format(stash.id, job, suffix, tostring(slots), tostring(weight))
end

local function requestOpenStash(stashId)
    local response = lib.callback.await('stashcreator:server:openStash', false, stashId)
    if not response or not response.ok then
        notify(response and response.message or 'Nepovedlo se otevrit stash.', 'error')
        return
    end
end

local function openEditDialog(stash)
    local input = lib.inputDialog('Upravit stash', {
        {
            type = 'input',
            label = 'Label',
            required = true,
            default = stash.label,
            min = 1
        },
        {
            type = 'input',
            label = 'ID',
            required = true,
            default = stash.id,
            min = 1
        },
        {
            type = 'input',
            label = 'Job name (nepovinne)',
            required = false,
            default = stash.job or ''
        },
        {
            type = 'number',
            label = 'Job grade minimum',
            required = true,
            default = tonumber(stash.jobGrade) or 0,
            min = 0,
            max = 100
        },
        {
            type = 'number',
            label = 'Slots',
            required = true,
            default = tonumber(stash.slots) or Config.DefaultSlots,
            min = 1,
            max = 500
        },
        {
            type = 'number',
            label = 'Weight',
            required = true,
            default = tonumber(stash.weight) or Config.DefaultWeight,
            min = 1000,
            max = 5000000
        },
        {
            type = 'checkbox',
            label = 'Soukromy (osobni)',
            checked = stash.private == true
        },
        {
            type = 'checkbox',
            label = 'Presunout na moji aktualni pozici',
            checked = false
        }
    })

    if not input then return end

    local coords = stash.coords
    if input[8] then
        local ped = PlayerPedId()
        local pedCoords = GetEntityCoords(ped)
        coords = { x = pedCoords.x, y = pedCoords.y, z = pedCoords.z }
    end

    local payload = {
        oldId = stash.id,
        label = input[1],
        id = input[2],
        job = input[3],
        jobGrade = input[4],
        slots = input[5],
        weight = input[6],
        private = input[7],
        coords = coords
    }

    local response = lib.callback.await('stashcreator:server:updateStash', false, payload)
    if not response or not response.ok then
        notify(response and response.message or 'Nepovedlo se upravit stash.', 'error')
        return
    end

    notify(response.message or 'Stash byl upraven.', 'success')
end

local function findClosestStash()
    local pedCoords = GetEntityCoords(PlayerPedId())
    local closest, closestDistance

    for i = 1, #stashes do
        local stash = stashes[i]
        local stashCoords = vec3(stash.coords.x, stash.coords.y, stash.coords.z)
        local distance = #(pedCoords - stashCoords)

        if not closestDistance or distance < closestDistance then
            closest = stash
            closestDistance = distance
        end
    end

    return closest, closestDistance
end

local function openEditClosestStash()
    if not canManage then
        notify('Na upravu stashu nemas opravneni.', 'error')
        return
    end

    local closest, distance = findClosestStash()
    if not closest then
        notify('Zadne stashe nejsou vytvorene.', 'inform')
        return
    end

    local maxDistance = tonumber(Config.EditClosestDistance) or 6.0
    if not distance or distance > maxDistance then
        notify(('Nejblizsi stash je moc daleko (%.1fm / max %.1fm).'):format(distance or 0.0, maxDistance), 'error')
        return
    end

    openEditDialog(closest)
end

local function openEditListMenu()
    if not canManage then
        notify('Na upravu stashu nemas opravneni.', 'error')
        return
    end

    if #stashes == 0 then
        notify('Zadne stashe nejsou vytvorene.', 'inform')
        return
    end

    local options = {}

    for i = 1, #stashes do
        local stash = stashes[i]

        options[#options + 1] = {
            title = stash.label,
            description = buildStashDescription(stash),
            onSelect = function()
                openEditDialog(stash)
            end
        }
    end

    lib.registerContext({
        id = 'stashcreator_edit_list',
        title = 'Vyber stash pro upravu',
        options = options
    })

    lib.showContext('stashcreator_edit_list')
end

local function openCreateMenu()
    if not canManage then
        notify('Na vytvareni stashu nemas opravneni.', 'error')
        return
    end

    local input = lib.inputDialog('Vytvorit stash', {
        {
            type = 'input',
            label = 'Label',
            required = true,
            min = 1
        },
        {
            type = 'input',
            label = 'ID',
            required = true,
            min = 1
        },
        {
            type = 'input',
            label = 'Job name (nepovinne)',
            required = false
        },
        {
            type = 'number',
            label = 'Job grade minimum',
            required = true,
            default = 0,
            min = 0,
            max = 100
        },
        {
            type = 'number',
            label = 'Slots',
            required = true,
            default = Config.DefaultSlots,
            min = 1,
            max = 500
        },
        {
            type = 'number',
            label = 'Weight',
            required = true,
            default = Config.DefaultWeight,
            min = 1000,
            max = 5000000
        },
        {
            type = 'checkbox',
            label = 'Soukromy (osobni na charid)',
            checked = false
        }
    })

    if not input then return end

    local ped = PlayerPedId()
    local coords = GetEntityCoords(ped)

    local payload = {
        label = input[1],
        id = input[2],
        job = input[3],
        jobGrade = input[4],
        slots = input[5],
        weight = input[6],
        private = input[7],
        coords = {
            x = coords.x,
            y = coords.y,
            z = coords.z
        }
    }

    local response = lib.callback.await('stashcreator:server:createStash', false, payload)
    if not response or not response.ok then
        notify(response and response.message or 'Nepovedlo se vytvorit stash.', 'error')
        return
    end

    notify(response.message or 'Stash vytvoren na tvoji pozici.', 'success')
end

local function openMainMenu()
    if not canManage then
        notify('Na otevreni spravy stashu nemas opravneni.', 'error')
        return
    end

    lib.registerContext({
        id = 'stashcreator_main',
        title = 'Stash Creator',
        options = {
            {
                title = 'Vytvorit stash na moji pozici',
                description = 'Aktuální pozice',
                icon = 'plus',
                onSelect = openCreateMenu
            },
            {
                title = 'Upravit nejblizsi stash',
                description = ('Pouzij /%s closest pro rychly edit nejblizsiho stashu.'):format(Config.AdminCommand),
                icon = 'location-dot',
                onSelect = openEditClosestStash
            },
            {
                title = 'Upravit ze seznamu',
                description = 'Vybere stash ze seznamu vsech ulozenych.',
                icon = 'pen',
                onSelect = openEditListMenu
            }
        }
    })

    lib.showContext('stashcreator_main')
end

local function rebuildZones()
    removeAllZones()

    for i = 1, #stashes do
        local stash = stashes[i]
        local coords = vec3(stash.coords.x, stash.coords.y, stash.coords.z)

        local options = {
            {
                name = ('stashcreator_open_%s'):format(stash.id),
                icon = 'fa-solid fa-box-open',
                label = ('Otevrit stash: %s'):format(stash.label),
                distance = Config.TargetDistance,
                onSelect = function()
                    requestOpenStash(stash.id)
                end
            }
        }

        local zoneId = exports.ox_target:addSphereZone({
            coords = coords,
            radius = Config.TargetRadius,
            debug = Config.DebugZones,
            options = options
        })

        zoneIds[#zoneIds + 1] = zoneId
    end
end

local function bootstrapData()
    local bootstrap = lib.callback.await('stashcreator:server:getBootstrap', false)
    if not bootstrap then
        notify('Nepovedlo se nacist seznam stashu.', 'error')
        return
    end

    canManage = bootstrap.canManage == true
    stashes = bootstrap.stashes or {}
    rebuildZones()
end

RegisterNetEvent('stashcreator:client:sync', function(serverStashes)
    stashes = serverStashes or {}
    rebuildZones()
end)

RegisterNetEvent('esx:playerLoaded', function()
    Wait(1000)
    bootstrapData()
end)

RegisterCommand(Config.AdminCommand, function(_, args)
    local sub = args and args[1] and string.lower(args[1]) or ''

    if sub == 'closest' then
        openEditClosestStash()
        return
    end

    if sub == 'create' then
        openCreateMenu()
        return
    end

    openMainMenu()
end, false)

CreateThread(function()
    Wait(2000)
    bootstrapData()
end)