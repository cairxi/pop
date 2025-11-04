local ffi = require('ffi')
local dats = require('ffxi.dats')
local chat = require('chat')

ffi.cdef[[
    bool FlashWindow(HWND hWnd, bool bInvert);
    HWND FindWindowA(const char* lpClassName, const char* lpWindowName);
]]

local C = ffi.C

local format_time_difference = function(t)
    local tdif = math.abs(t)
    local hours   = string.format('%02d', math.floor(tdif / 3600))
    local minutes = string.format('%02d', math.floor((tdif / 60) - (hours * 60)))
    local seconds = string.format('%02d', math.floor(tdif % 60))
    return '-'  .. hours .. ':' .. minutes .. ':' .. seconds
end

local flash_window = function()
    local player = AshitaCore:GetMemoryManager():GetParty():GetMemberName(0)
    if player then
        local hwnd = C.FindWindowA('FFXiClass', player)
        if hwnd then
            C.FlashWindow(hwnd, true)
        end
    end
end

local populate_entity_names = function(zid, zsubid)
    local entities = {}

    local file = dats.get_zone_npclist(zid, zsubid)
    if (file == nil or file:len() == 0) then
        return {}, false
    end

    local f = io.open(file, 'rb')
    if (f == nil) then
        return {}, false
    end

    local size = f:seek('end')
    f:seek('set', 0x20)

    if (size == 0 or ((size - math.floor(size / 0x20) * 0x20) ~= 0)) then
        f:close()
        return {}, false
    end

    for _ = 1, ((size / 0x20) - 0x01) do
        local data = f:read(0x20)
        local name, id = struct.unpack('c28L', data)
        local namestr = ffi.string(name)
        table.insert(entities, { bit.band(id, 0x0FFF), id, tostring(id), namestr, namestr:lower() })
    end

    f:close()
    return entities, true
end

local play_pop_sound = function()
    ashita.misc.play_sound(addon.path:append('\\sounds\\pop.wav'))
end

local print_pop_message = function(index, name)
    local name = name or '(Unknown)'
    print(chat.header(addon.name) + chat.message('['.. index .. '] ') + chat.success(name))
end

return {
    format_time_difference = format_time_difference,
    populate_entity_names = populate_entity_names,
    play_pop_sound = play_pop_sound,
    print_pop_message = print_pop_message,
    flash_window = flash_window
}
