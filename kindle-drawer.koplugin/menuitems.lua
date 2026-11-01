-- KOReader menu item semantics shared by the Kindle-style menu and the bottom
-- drawer's inline menu pages. Rules mirror ui/widget/touchmenu.lua. A host
-- provides pushPage(item, sub_item_table), updateItems(), closeMenu(),
-- closeConfigDialog() and onInput(input), and item callbacks get it as
-- touchmenu_instance.
local Utf8Proc = require("ffi/utf8proc")
local UIManager = require("ui/uimanager")
local tr = require("l10n").tr

local M = {}

-- The first "character" can be malformed UTF-8, so the call stays guarded.
local function caseMap(fn, fallback)
    if not fn then return fallback end
    return function(c)
        local ok, result = pcall(fn, c)
        if ok and type(result) == "string" then return result end
        return fallback(c)
    end
end
local upper = caseMap(Utf8Proc.uppercase_dumb or Utf8Proc.uppercase, string.upper)
local lower = caseMap(Utf8Proc.lowercase_dumb or Utf8Proc.lowercase, string.lower)
M.lower = lower

-- Display-only capitalization; KOReader's strings stay untouched.
function M.ucfirst(text)
    if type(text) ~= "string" or text == "" then return text end
    local first = text:match("^[%z\1-\127\194-\244][\128-\191]*")
    if not first then return text end
    local rest = text:sub(#first + 1)
    local second = rest:match("^[%z\1-\127\194-\244][\128-\191]*")
    if upper(first) == first then return text end -- not a lowercase letter
    if second and lower(second) ~= second then return text end -- "eReader", "iOS"
    return upper(first) .. rest
end

M.upper = upper

function M.splitLabel(text)
    local label, value = text:match("^(.-):%s+(.-)%s*$")
    if label and label ~= "" and value ~= "" then return label, value end
    return text, nil
end

function M.text(item)
    local text = item.text_func and item.text_func() or item.text
    return text ~= nil and tostring(text) or ""
end
function M.enabled(item)
    local enabled = item.enabled
    if item.enabled_func then enabled = item.enabled_func() end
    return enabled ~= false
end
function M.checked(item)
    local checked = item.checked
    if item.checked_func then checked = item.checked_func() end
    return checked and true or false
end
function M.hasSub(item)
    return item.sub_item_table ~= nil or item.sub_item_table_func ~= nil
end
function M.subTable(item)
    return item.sub_item_table_func and item.sub_item_table_func() or item.sub_item_table
end
-- TouchMenu's id for updateItems(nil, menu_item_id).
function M.itemId(item)
    item.menu_item_id = item.menu_item_id or tostring(item)
    return item.menu_item_id
end

-- Parent of an all-radio submenu shows the selected child. Only static tables:
-- sub_item_table_func may be expensive, TouchMenu runs it only on select.
function M.radioValue(items)
    for _, child in ipairs(items) do
        if type(child) == "table" and not child.radio then return nil end
    end
    for _, child in ipairs(items) do
        if type(child) == "table" and M.checked(child) then return M.text(child) end
    end
end

-- Drop, in place, captions ({kd_caption=...}) with no row before the next caption or the end.
function M.dropEmptyCaptions(list)
    local n, len = 0, #list
    for i = 1, len do
        local item, nxt = list[i], list[i + 1]
        if not item.kd_caption or (nxt and not nxt.kd_caption) then n = n + 1; list[n] = item end
    end
    for i = n + 1, len do list[i] = nil end
    return list
end

-- wanted in list by identity, else by text: sub_item_table_func builds new tables on every call.
function M.findIn(list, wanted)
    for _, candidate in ipairs(list or {}) do
        if candidate == wanted then return candidate end
    end
    local text = M.text(wanted)
    for _, candidate in ipairs(list or {}) do
        if type(candidate) == "table" and not candidate.kd_caption and M.text(candidate) == text then return candidate end
    end
end

--[[ Depth-first walk over items and their submenus, captions skipped. visit(item, chain)
gets the live chain from the top down to item; returning true stops the walk.
opts.funcs also runs sub_item_table_func (like TouchMenu's search), opts.search
honours ignored_by_menu_search, opts.depth limits the depth (10). ]]
function M.walk(list, visit, opts)
    opts = opts or {}
    local max, chain = opts.depth or 10, {}
    local function skip(t) return opts.search and t.ignored_by_menu_search end
    local function walk(items, depth)
        if depth > max or type(items) ~= "table" or skip(items) then return false end
        for _, item in ipairs(items) do
            if type(item) == "table" and not item.kd_caption and not skip(item) then
                chain[#chain + 1] = item
                if visit(item, chain) then return true end
                local sub = item.sub_item_table
                if opts.funcs then
                    local ok, result = pcall(M.subTable, item)
                    sub = ok and result or nil
                end
                if walk(sub, depth + 1) then return true end
                chain[#chain] = nil
            end
        end
        return false
    end
    walk(list, 1)
end

-- Chain of items from the top of list down to the first item matching pred, or nil.
function M.findChain(list, pred, depth)
    local found
    M.walk(list, function(item, chain)
        if pred(item) then
            found = {}
            for i, v in ipairs(chain) do found[i] = v end
            return true
        end
    end, { depth = depth })
    return found
end

-- Display data of one item: kind "radio" or "item", label, value or switch,
-- chevron, enabled, and an optional translated subtitle from hints.
function M.describe(item, hints)
    local text = M.text(item)
    local row = { kind = "item", item = item, enabled = M.enabled(item) }
    local checked = M.checked(item)
    if item.radio then
        row.kind, row.label, row.on = "radio", M.ucfirst(text), checked
        return row
    end
    row.chevron = M.hasSub(item)
    if item.checked_func or item.checked ~= nil then
        row.switch, row.label = checked, M.ucfirst(text)
    else
        local label, value = text, nil
        local mandatory = item.mandatory_func and item.mandatory_func() or item.mandatory
        if mandatory ~= nil and mandatory ~= "" then
            value = tostring(mandatory)
        else
            label, value = M.splitLabel(text)
        end
        if not value and type(item.sub_item_table) == "table" then value = M.radioValue(item.sub_item_table) end
        row.label, row.value = M.ucfirst(label), value and M.ucfirst(value)
    end
    local hint = item.hint or (hints and hints[item.id])
    if hint then row.sub = tr(hint) end
    return row
end

-- Host methods, installed into each host class.
local mixin = {}

function mixin:onMenuSelect(item, tap_on_checkmark)
    self:closeConfigDialog()
    if tap_on_checkmark and item.checkmark_callback then
        item.checkmark_callback()
        self:updateItems()
        return true
    end
    if item.tap_input or item.tap_input_func then
        if not item.keep_menu_open then self:closeMenu() end
        self:onInput(item.tap_input or item.tap_input_func())
        return true
    end
    local sub_item_table = M.subTable(item)
    if sub_item_table then
        if #sub_item_table > 0 then self:pushPage(item, sub_item_table) end
        return true
    end
    local callback = item.callback_func and item.callback_func() or item.callback
    if callback then
        -- Callbacks get the host as touchmenu_instance, like TouchMenu.
        callback(self)
        if item.checked or item.checked_func then
            if not (item.check_callback_updates_menu or item.check_callback_closes_menu) then self:updateItems() end
        elseif not item.keep_menu_open then
            self:closeMenu()
        end
    end
    return true
end

function mixin:onMenuHold(item, text_truncated)
    self:closeConfigDialog()
    if item.hold_input or item.hold_input_func then
        if item.hold_keep_menu_open == false then self:closeMenu() end
        self:onInput(item.hold_input or item.hold_input_func())
        return true
    end
    local hold_callback = item.hold_callback_func and item.hold_callback_func() or item.hold_callback
    if hold_callback then
        if item.hold_keep_menu_open == false then self:closeMenu() end
        hold_callback(self, item)
        return true
    end
    self:showHelp(item, text_truncated)
    return true
end

function mixin:showHelp(item, text_truncated)
    local help_text = item.help_text_func and item.help_text_func(self) or item.help_text
    local InfoMessage = require("ui/widget/infomessage")
    if help_text then
        UIManager:show(InfoMessage:new{ text = help_text })
    elseif text_truncated then
        UIManager:show(InfoMessage:new{ text = M.text(item), show_icon = false })
    end
end

-- Copy the host methods a class does not define itself.
function M.install(class)
    for name, fn in pairs(mixin) do
        if rawget(class, name) == nil then class[name] = fn end
    end
    return class
end

return M
