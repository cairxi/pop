addon.name = 'pop'
addon.author = 'cair'
addon.version = '1.0'

local settings = require('settings')
local chat = require('chat')
local helpers = require('helpers')
local ui = require('ui')
local commands = require('commands')

local defaults = {
    watch = {
        ids = {},
        names = {},
    },
    tods = {},
    reminder = 60 * 5,
    flash = true,
    sound = true,
    ui = { true },
    tod = { true },
}

local config = settings.load(defaults)

-- State tracking
local entities = {}
local announced = {}
local dynamic_names = {}
local despawning = {}
local claim_tracking = {}
local target_index = 0

-- UI visibility state
local visible = config.ui
local tod_visible = config.tod

-- Watch/unwatch functions
local watch_named_entity = function(name)
    config.watch.names[name] = true
end

local unwatch_named_entity = function(name)
    config.watch.names[name] = nil
end

-- Core notification logic
local handle_notify = function(index, name)
    local prev = announced[index] or 0
    local now = os.time()
    local dif = now - prev
    if dif < config.reminder then
        return
    end
    announced[index] = now
    if config.flash then helpers.flash_window() end
    if config.sound then helpers.play_pop_sound() end
    helpers.print_pop_message(index, name)
end

local add_tod = function(index, id, name)
    local now = os.time()
    local date = os.date('%X', now)
    local name = name or '(Unknown)'
    config.tods[id] = {index, name, now, date}
    print(chat.header(addon.name) + chat.message('[' .. index .. '] ') + chat.success(name) + chat.message( ' despawned at ') + chat.success(date))
    settings.save()
end

local handle_unrender = function(index, id, name)
    if announced[index] and despawning[index] then
        add_tod(index, id, name)
    end
    claim_tracking[index] = nil
    despawning[index] = nil
    announced[index] = nil
end

local fetch_name = function(index)
    if index < 0x700 and entities[index] then
        return entities[index][4]
    end

    return dynamic_names[index] or '(Unknown)'
end

-- Packet handlers
local handle_entity = function(data)
    local unpack = struct.unpack
    local band = bit.band
    local index = unpack('H', data, 0x09)
    local id = unpack('I', data, 0x05)
    local mask = unpack('B', data, 0x0B)

    if band(mask, 32) == 32 then
        local name = fetch_name(index)
        handle_unrender(index, id, name)
        return
    end

    if band(mask, 8) == 8 and index >= 0x700 then
        local name = unpack('c16', data, 0x35)
        dynamic_names[index] = name
    end

    if (not claim_tracking[index] or claim_tracking[index] == 0) then
        local name = fetch_name(index)
        if config.watch.ids[id] or config.watch.names[name] then
            handle_notify(index, name)
        end
    end
    
    if band(mask, 2) == 2 then
        claim_tracking[index] = unpack('I', data, 0x2D)
    end
end

local handle_spawn_despawn = function(data)
    local unpack = struct.unpack
    local index = unpack('H', data, 0x11)
    local id = unpack('I', data, 0x05)
    local kd = unpack('c4', data, 0x0D)
    if kd == 'kesu' then
        despawning[index] = true
    elseif kd == 'deru' and config.watch.ids[id] then
        local name = fetch_name(index)
        handle_notify(index, name)
    end
end

-- Event handlers
ashita.events.register('packet_in', 'packet_in_cb', function (e)
    if (e.blocked) then
        return
    end

    -- Entity update
    if e.id == 0x0E then
        handle_entity(e.data_modified)
        return
    end

    -- Spawn/Despawn animation
    if e.id == 0x038 then
        handle_spawn_despawn(e.data_modified)
    end

    -- Zone
    if e.id == 0x0A then
        announced = {}
        claim_tracking = {}
        dynamic_names = {}
        local zone = struct.unpack('H', e.data_modified, 0x31)
        local subid = struct.unpack('H', e.data_modified, 0x9F)
        entities = helpers.populate_entity_names(zone, subid)
    end
end)

ashita.events.register('packet_out', 'packet_out_cb', function(e)
    if e.id ~= 0x015 then
        return
    end
    
    target_index = struct.unpack('H', e.data_modified, 0x17)
end)

ashita.events.register('d3d_present', 'present_cb', function ()
    ui.draw_main_window(visible, config, entities, target_index, watch_named_entity, unwatch_named_entity)
    ui.draw_tod_window(tod_visible, config)
end)

ashita.events.register('command', 'command_cb', function (e)
    local args = e.command:args()
    local handled = commands.handle_command(args, config, visible, tod_visible)
    if handled then
        e.blocked = true
    end
end)

settings.register('settings', 'settings_update', function (s)
    if s then
        config = s
    end
    settings.save()
end)

-- Initialize entities on load
entities = helpers.populate_entity_names(AshitaCore:GetMemoryManager():GetParty():GetMemberZone(0), 0)
