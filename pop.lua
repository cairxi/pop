addon.name = 'pop'
addon.author = 'cair'
addon.version = '1.0'

local ffi = require('ffi')
local imgui = require('imgui')
local settings = require('settings')
local dats = require('ffxi.dats')
local chat = require('chat')

ffi.cdef[[
    bool FlashWindow(HWND hWnd, bool bInvert);
    HWND FindWindowA(const char* lpClassName, const char* lpWindowName);
]]

local C = ffi.C

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

local entities = {}
local announced = {}
local dynamic_names = {}
local despawning = {}
local claim_tracking = {}

local flash_window = function()
    local player = AshitaCore:GetMemoryManager():GetParty():GetMemberName(0)
    if player then
        local hwnd = C.FindWindowA('FFXiClass', player)
        if hwnd then
            C.FlashWindow(hwnd, true)
        end
    end
end

local play_pop_sound = function()
    ashita.misc.play_sound(addon.path:append('\\sounds\\pop.wav'))
end

local print_pop_message = function(index, name)
    local name = name or '(Unknown)'
    print(chat.header(addon.name) + chat.message('['.. index .. '] ') + chat.success(name))
end

local watch_named_entity = function(name)
    config.watch.names[name] = true
end

local unwatch_named_entity = function(name)
    config.watch.names[name] = nil
end

local handle_notify = function(index, name)
    local prev = announced[index] or 0
    local now = os.time()
    local dif = now - prev
    if dif < config.reminder then
        return
    end
    announced[index] = now
    if config.flash then flash_window() end
    if config.sound then play_pop_sound() end
    print_pop_message(index, name)
end

local add_tod = function(index, id, name)
    local now = os.time()
    local date = os.date('%X', now)
    local name = name or '(Unknown)'
    config.tods[id] = {index, name, now, date}
    print(chat.header(addon.name) + chat.message('[' .. index .. '] ') + chat.success(name) + chat.message( ' despawned at ') + chat.success(date))
end

local handle_unrender = function(index, id, name)
    if announced[index] and despawning[index] then
        add_tod(index, id, name)
    end
    despawning[index] = nil
    announced[index] = nil
end

local populate_entity_names = function(zid, zsubid)
    entities = {}

    local file = dats.get_zone_npclist(zid, zsubid)
    if (file == nil or file:len() == 0) then
        return false
    end

    local f = io.open(file, 'rb')
    if (f == nil) then
        return false
    end

    local size = f:seek('end')
    f:seek('set', 0x20)

    if (size == 0 or ((size - math.floor(size / 0x20) * 0x20) ~= 0)) then
        f:close()
        return false
    end

    for _ = 1, ((size / 0x20) - 0x01) do
        local data = f:read(0x20)
        local name, id = struct.unpack('c28L', data)
        local namestr = ffi.string(name)
        table.insert(entities, { bit.band(id, 0x0FFF), id, tostring(id), namestr, namestr:lower() })
    end

    f:close()
    return true
end

local fetch_name = function(index)
    if index < 0x700 and entities[index] then
        return entities[index][4]
    end

    return dynamic_names[index] or '(Unknown)'
end

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
    local kd = unpack('c4', data, 0x0D)
    if kd == 'kesu' then
        despawning[index] = true
    end
end

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
        populate_entity_names(zone, subid)
    end

end)

local target_index = 0

ashita.events.register('packet_out', 'packet_out_cb', function(e)
    if e.id ~= 0x015 then
        return
    end
    
    target_index = struct.unpack('H', e.data_modified, 0x17)
end)

local gui_flags = bit.bor(ImGuiWindowFlags_NoSavedSettings, ImGuiWindowFlags_NoFocusOnAppearing, ImGuiWindowFlags_NoScrollbar, ImGuiWindowFlags_NoScrollWithMouse)
local visible = config.ui
local tod_visible = config.tod
local selected_color = { 0, 0.75, 0, 1.0 }
local search_term = { '' }
local entity_to_add = { '' }
local show_selected = { false }

local draw_main_window = function()
    if visible[1] then
        imgui.SetNextWindowBgAlpha(0.8)
        imgui.SetNextWindowSizeConstraints({ FLT_MIN, FLT_MIN, }, { 800, 800, })
        if(imgui.Begin('Pop!', visible, gui_flags)) then
            if imgui.BeginTabBar("Tracking Types") then
                if imgui.BeginTabItem("Zone Index List") then

                    imgui.Dummy({0, 1})
                    imgui.BeginGroup()
                    imgui.Text('Filter: ')
                    imgui.SameLine()
                    imgui.InputText('##search_term', search_term, 256)
                    imgui.SameLine()
                    imgui.Checkbox('Selected', show_selected)
                    imgui.EndGroup()
                    imgui.Dummy({0, .5})
                    imgui.SetNextWindowBgAlpha(0)

                    if imgui.BeginChild("Scrollable Index List") then
                        for _, v in ipairs(entities) do

                            local lower_name = v[5]
                            local term = search_term[1]
                            local index = v[1]
                            local id = v[2]
                            local tag = v[3]
                            local name = v[4]
                            local checked = config.watch.ids[id] or false

                            if (not show_selected[1] or (show_selected[1] and checked)) and 
                                (term:len() < 1 or string.find(lower_name, term:lower())) then

                                local changed = imgui.Checkbox('##' .. tag, { checked })
                                if changed then
                                    config.watch.ids[id] = not checked and true or nil
                                end
                                imgui.SameLine()
                                if index == target_index then
                                    imgui.TextColored(selected_color, '[' .. index .. '] '.. name .. ' (' .. id .. ')')
                                else
                                    imgui.Text('[' .. index .. '] '.. name .. ' (' .. id .. ')')
                                end
                            end
                        end
                        imgui.EndChild()
                    end
                    imgui.EndTabItem()
                end

                if imgui.BeginTabItem("By Name") then

                    imgui.Dummy({0, 1})
                    imgui.BeginGroup()
                    imgui.Text('Add entity: ')
                    imgui.SameLine()
                    if imgui.InputText('##entity_to_add', entity_to_add, 17, ImGuiInputTextFlags_EnterReturnsTrue) then
                        watch_named_entity(entity_to_add[1])
                    end
                    imgui.SameLine()
                    if imgui.Button('+##add-entity') then
                        watch_named_entity(entity_to_add[1])
                    end
                    imgui.EndGroup()
                    imgui.Dummy({0, 1})
                    imgui.SetNextWindowBgAlpha(0)

                    if imgui.BeginChild("Scrollable Name List") then
                        for k,_ in pairs(config.watch.names) do
                            if imgui.Button('-##remove-' .. k) then
                                unwatch_named_entity(k)
                            end
                            imgui.SameLine()
                            imgui.Text(k)
                        end
                        imgui.EndChild()
                    end

                    imgui.EndTabItem()
                end

                imgui.EndTabBar()
            end
            imgui.End()
        end
    end
end

local format_time_difference = function(t)
    local tdif = math.abs(t)
    local hours   = string.format('%02d', math.floor(tdif / 3600))
    local minutes = string.format('%02d', math.floor((tdif / 60) - (hours * 60)))
    local seconds = string.format('%02d', math.floor(tdif % 60))
    return '-'  .. hours .. ':' .. minutes .. ':' .. seconds
end

local draw_tod_window = function()
    if tod_visible[1] then
        local tods = config.tods
        imgui.SetNextWindowBgAlpha(0.8)
        imgui.SetNextWindowSizeConstraints({ FLT_MIN, FLT_MIN, }, { 400, 400, })
        if(imgui.Begin('Recent TODs', tod_visible, gui_flags)) then
            for k,v in pairs(tods) do
                local dif = v[3] - os.time()
                local foramtted = format_time_difference(dif)
                if imgui.Button('-##remove-tod-' .. k) then
                    tods[k] = nil
                end
                imgui.SameLine()
                imgui.Text('[' .. v[1] .. '] '.. v[2] .. ' : ' .. v[4] .. ' |')
                imgui.SameLine()
                imgui.TextColored({ 0.75, 0.75, 0, 1.0 }, foramtted)
            end
            imgui.End()
        end
    end
end

ashita.events.register('d3d_present', 'present_cb', function ()
    draw_main_window()
    draw_tod_window()
end)

ashita.events.register('command', 'command_cb', function (e)
    local args = e.command:args()
    if (#args == 0 or not args[1]:any('/pop')) then
        return
    end

    e.blocked = true

    if #args == 1 then
        visible[1] = not visible[1]
        return
    end

    if args[2]:any('tod','t') then
        tod_visible[1] = not tod_visible[1]
    end

    if args[2]:any('sound','s') then
        config.sound = not config.sound
        local msg = config.sound and chat.success('[ON]') or chat.error('[OFF]')
        print(chat.header(addon.name) + chat.message('Sound alerts: ') + msg)
    end

    if args[2]:any('flash','f') then
        config.flash = not config.flash
        local msg = config.flash and chat.success('[ON]') or chat.error('[OFF]')
        print(chat.header(addon.name) + chat.message('Flash taskbar: ') + msg)
    end

end)

ashita.events.register('unload', 'unload_cb', settings.save)

populate_entity_names(AshitaCore:GetMemoryManager():GetParty():GetMemberZone(0), 0)
