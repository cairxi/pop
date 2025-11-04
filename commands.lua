local chat = require('chat')

local commands = {}

commands.handle_command = function(args, config, visible, tod_visible)
    if (#args == 0 or not args[1]:any('/pop')) then
        return false
    end

    if #args == 1 then
        visible[1] = not visible[1]
        return true
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

    if args[2]:any('reminder','r') then
        local timer = tonumber(args[3]) or config.remminder
        print(chat.header(addon.name) + chat.message('Reminder timer: ') + timer)
    end

    return true
end

return commands
