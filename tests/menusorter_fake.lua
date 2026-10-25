-- Test double of frontend/ui/menusorter.lua with the behaviour the plugin relies on:
-- ids on placed items, containers wrapped as {id, text, hold_callback, sub_item_table},
-- separators, KOMenu:disabled, "KOMenu:menu_buttons" removed before orphans, orphans in
-- key order with "NEW: " unless hinted, and a nil index on an unknown sorting_hint.
local SEP = "----------------------------"
local MS = { orphaned_prefix = "NEW: ", separator = { id = SEP, text = "KOMenu:separator" } }

function MS:mergeAndSort(_, item_table, order) return self:sort(item_table, order) end

function MS:findById(tbl, needle)
    local queue = {}
    for _, item in pairs(tbl) do if type(item) == "table" then queue[#queue + 1] = item end end
    local i = 1
    while queue[i] do
        local v = queue[i]
        if v.id == needle then return v end
        local sub = v.sub_item_table or v
        for _, item in pairs(sub) do
            if type(item) == "table" and item.id then queue[#queue + 1] = item end
        end
        i = i + 1
    end
end

function MS:sort(item_table, order)
    local menu_table, sub_menus = {}, {}
    for order_id, list in pairs(order) do
        if item_table[order_id] ~= nil then
            menu_table[order_id] = item_table[order_id]
            menu_table[order_id].id = order_id
            local n = 0
            for _, id in ipairs(list) do
                if id == SEP then
                    if n > 0 then menu_table[order_id][n].separator = true end
                elseif item_table[id] ~= nil and order[id] then
                    sub_menus[#sub_menus + 1] = id
                    n = n + 1; menu_table[order_id][n] = { id = id }
                elseif item_table[id] ~= nil then
                    item_table[id].id = id
                    n = n + 1; menu_table[order_id][n] = item_table[id]
                    item_table[id] = nil
                end
            end
        end
    end
    local changed = true
    while changed do
        changed = false
        for _, sub in ipairs(sub_menus) do
            if menu_table[sub] ~= nil then
                local pos = self:findById(menu_table["KOMenu:menu_buttons"], sub)
                if pos then
                    changed = true
                    pos.text, pos.hold_callback, pos.sub_item_table = menu_table[sub].text, menu_table[sub].hold_callback, menu_table[sub]
                    menu_table[sub], item_table[sub] = nil, nil
                end
            end
        end
    end
    local buttons, out = menu_table["KOMenu:menu_buttons"], {}
    for _, b in ipairs(buttons) do if b.sub_item_table then out[#out + 1] = b.sub_item_table end end
    for _, id in ipairs(order["KOMenu:disabled"] or {}) do item_table[id] = nil end
    item_table["KOMenu:menu_buttons"] = nil
    local keys = {}
    for k in pairs(item_table) do keys[#keys + 1] = k end
    table.sort(keys)
    for _, k in ipairs(keys) do
        local v = item_table[k]
        if v.text and v.new ~= true then
            v.id = k
            if not v.sorting_hint then v.text = self.orphaned_prefix .. v.text end
            v.new = true
        end
        if v.sorting_hint then
            local hint = self:findById(out, v.sorting_hint)
            hint = hint.sub_item_table or hint -- errors on an unknown hint, like KOReader
            table.insert(hint, v)
        else
            table.insert(out[1], v)
        end
    end
    return out
end

return MS
