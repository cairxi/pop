local imgui = require('imgui')
local helpers = require('helpers')

local ui = {}

-- UI state variables
local gui_flags = bit.bor(ImGuiWindowFlags_NoSavedSettings, ImGuiWindowFlags_NoFocusOnAppearing, ImGuiWindowFlags_NoScrollbar, ImGuiWindowFlags_NoScrollWithMouse)
local selected_color = { 0, 0.75, 0, 1.0 }
local search_term = { '' }
local entity_to_add = { '' }
local show_selected = { false }

ui.draw_main_window = function(visible, config, entities, target_index, watch_named_entity, unwatch_named_entity)
    if not visible[1] then
        return
    end
    
    imgui.SetNextWindowBgAlpha(0.8)
    imgui.SetNextWindowSizeConstraints({ FLT_MIN, FLT_MIN, }, { 800, 800, })
    
    if not imgui.Begin('Pop!', visible, gui_flags) then
        return
    end
    
    if imgui.BeginTabBar("Tracking Types") then
        -- Zone Index List Tab
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

        -- By Name Tab
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

ui.draw_tod_window = function(tod_visible, config)
    if not tod_visible[1] then
        return
    end
    
    local tods = config.tods
    imgui.SetNextWindowBgAlpha(0.8)
    imgui.SetNextWindowSizeConstraints({ FLT_MIN, FLT_MIN, }, { 400, 400, })
    
    if not imgui.Begin('Recent TODs', tod_visible, gui_flags) then
        return
    end
    
    for k,v in pairs(tods) do
        local dif = v[3] - os.time()
        local formatted = helpers.format_time_difference(dif)
        if imgui.Button('-##remove-tod-' .. k) then
            tods[k] = nil
        end
        imgui.SameLine()
        imgui.Text('[' .. v[1] .. '] '.. v[2] .. ' : ' .. v[4] .. ' |')
        imgui.SameLine()
        imgui.TextColored({ 0.75, 0.75, 0, 1.0 }, formatted)
    end
    imgui.End()
end

return ui
