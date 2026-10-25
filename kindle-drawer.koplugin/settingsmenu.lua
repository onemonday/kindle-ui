-- Kindle-style view of KOReader's top menu. Sections come from layout.lua and hold
-- KOReader's own items; selection, hold and refresh rules mirror ui/widget/touchmenu.lua
-- (menuitems.lua), and this widget offers the same surface to callbacks (touchmenu_instance).
local InputContainer = require("ui/widget/container/inputcontainer")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local TextWidget = require("ui/widget/textwidget")
local ImageWidget = require("ui/widget/imagewidget")
local Blitbuffer = require("ffi/blitbuffer")
local Device = require("device")
local UIManager = require("ui/uimanager")
local Event = require("ui/event")
local NetworkMgr = require("ui/network/manager")
local datetime = require("datetime")
local time = require("ui/time")
local Drawer = require("drawer")
local Items = require("menuitems")
local L10n = require("l10n")
local tr = L10n.tr
local Screen = Device.screen
local source = debug.getinfo(1, "S").source:sub(2)
local icon_dir = source:match("(.*/)") .. "icons/"

local function color(name, fallback)
    return Blitbuffer[name] or Blitbuffer[fallback] or Blitbuffer.COLOR_BLACK
end
local black, white = Blitbuffer.COLOR_BLACK, Blitbuffer.COLOR_WHITE
local c_value = color("COLOR_GRAY_3", "COLOR_DARK_GRAY")
local c_sub = color("COLOR_GRAY_5", "COLOR_DARK_GRAY")
local c_disabled = color("COLOR_GRAY", "COLOR_LIGHT_GRAY")
local c_divider = color("COLOR_GRAY_D", "COLOR_LIGHT_GRAY")
local c_border = Blitbuffer.COLOR_LIGHT_GRAY
local c_group = color("COLOR_GRAY_9", "COLOR_DARK_GRAY")

-- Geometry in design units of the approved mockup: its 420 x 560 CSS values,
-- drawn on a 512 x 683 screen (x0.82, the size of real Kindle Settings).
local STATUS_H, TITLE_H = 30, 48
local VIEW_TOP = STATUS_H + TITLE_H + 1
local ROW, ROW2, SEP, CAPTION, CAPTION_FIRST = 56, 68, 11, 40, 34
local PAD_L, PAD_R, PAD_R_SCROLL = 24, 32, 58
-- Right-hand row columns, shared by paintRow and the tap hit areas.
local CHEVRON_COL = 9 + 14 -- chevron icon + gap
local SWITCH_COL = 46 + 12 -- switch + gap
local SCROLLBAR_COL = 46
local POP_W, POP_ITEM = 236, 44
local FLING_MS, PAN_MS = 320, 80
local DESIGN_W, DESIGN_H = 512, 683
local WHEEL_ROWS = 3
local SEARCH_DEPTH = 8

local M = InputContainer:extend{
    modal = false, -- KOReader dialogs opened from items must stack above the menu
    covers_fullscreen = true,
    covers_header = true,
}
Items.install(M)
M.colors = { value = c_value, sub = c_sub, disabled = c_disabled, divider = c_divider, group = c_group }

-- Subtitles for non-obvious KOReader items, keyed by MenuSorter id.
-- The plugin's own items carry theirs in item.hint.
M.hints = {
    start_with = "Screen shown when KOReader starts",
    sort_mixed = "Folders are sorted together with books",
    screen_dpi = "Scales the interface; Auto uses the device value",
    calibre = "Wireless transfer from Calibre on your computer",
    localsend = "File transfer from a phone or computer",
    profiles = "Saved sets of settings you can switch between",
    news_downloader = "Downloads RSS feeds as books",
    find_book_in_calibre_catalog = "Finds books by title or author in Calibre libraries",
    opds = "Browse and download books from online libraries",
    page_overlap = "Marks the part of the previous page after turning",
    style_tweaks = "Overrides book styles: indents, footnotes, images",
    typography = "Language rules for hyphenation and line breaks",
    autowarmth = "By sunrise and sunset or on a schedule",
    screensaver = "Cover, image or message",
    screen_eink_opt = "Flashes on tap, refresh speed",
    keep_alive = "Temporarily prevents auto-sleep",
    language_support = "Japanese: word forms for dictionary lookup",
    vocabbuilder = "Cards with the words you looked up",
    show_filter = "New, reading, on hold, finished",
    doc_setting_tweak = "Book settings by folder",
    kindle_drawer = "Drawers, menu and Quick actions panel",
    plugin_management = "Turn plugins on and off, needs a restart",
    screen_notification = "Which pop-up messages to show",
}

local function freeRowTexts(rows)
    for _, row in ipairs(rows or {}) do
        if row.texts then
            for _, widget in pairs(row.texts) do widget:free() end
            row.texts = nil
        end
    end
end

function M:init()
    self.dimen = Geom:new{ x = 0, y = 0, w = Screen:getSize().w, h = Screen:getSize().h }
    -- 512 units across in portrait; landscape keeps the same row height.
    self.scale = math.min(self.dimen.w / DESIGN_W, self.dimen.h / DESIGN_H)
    self.W, self.H = self.dimen.w / self.scale, self.dimen.h / self.scale
    self.view_h = self.H - VIEW_TOP
    self.full_refresh = self.owner.settings.full_refresh == true
    self.lang = L10n.language()
    self.images, self.faces = {}, {}
    self.item_table_stack, self.path_stack = {}, {}
    self.titles, self.offsets = {}, {}
    self.at_root, self.offset, self.root_offset, self.page = true, 0, 0, 1
    local layout = self.layout_data or {}
    self.tab_item_table = layout.sections or {}
    self.book_page = layout.book
    local menu = self.menu
    -- KOReader reads menu_container[1].last_index when it closes its menu, and
    -- its "Menu search" calls menu_container[1]:onShowMenuSearch().
    local last = self.ui.document and menu.last_tab_index
        or G_reader_settings:readSetting("filemanagermenu_tab_index")
    self[1] = { last_index = last or 1, handleEvent = function() return false end,
        onShowMenuSearch = function() return self:onShowMenuSearch() end }
    self.ges_events = {}
    for _, name in ipairs({ "tap", "hold", "pan", "pan_release", "swipe", "multiswipe" }) do
        self.ges_events["KMenu_" .. name] = { GestureRange:new{ ges = name, range = self.dimen } }
    end
    self.key_events.Back = { { "Back" } }
    self.key_events.Close = { { "Menu" } }
    local Input = Device.input
    if Input and Input.group then
        self.key_events.NextPage = { { Input.group.PgFwd } }
        self.key_events.PrevPage = { { Input.group.PgBack } }
    end
    self:updateItems()
end

function M:now(ges)
    if ges and ges.time then return time.to_ms(ges.time) end
    return time.to_ms(time.now())
end

------------------------------------------------------------------------------
-- Rows and scrolling

function M:describe(item)
    local row = Items.describe(item, M.hints)
    row.h = row.sub and ROW2 or ROW
    return row
end

function M:layout()
    local rows = {}
    if self.at_root then
        for _, tab in ipairs(self.tab_item_table) do
            rows[#rows + 1] = { kind = "tab", key = tab.kd_key, label = tab.text, icon = tab.kd_icon, sub = tab.kd_hint,
                h = tab.kd_hint and ROW2 or ROW, enabled = true, chevron = true }
        end
    else
        local items = self.item_table
        -- Section pages group rows with captions; KOReader separators belong to its own tabs.
        local section = items.kd_section
        for i, item in ipairs(items) do
            if type(item) == "table" then
                item.idx = i
                if item.kd_caption then
                    rows[#rows + 1] = { kind = "caption", label = Items.upper(item.kd_caption),
                        h = #rows == 0 and CAPTION_FIRST or CAPTION }
                else
                    rows[#rows + 1] = self:describe(item)
                    if item.separator and not section and i < #items then rows[#rows + 1] = { kind = "sep", h = SEP } end
                end
            end
        end
    end
    local y = 0
    for _, row in ipairs(rows) do row.y = y; y = y + row.h end
    freeRowTexts(self.rows)
    self.rows, self.total = rows, y
    self.max = math.max(0, y - self.view_h)
    -- Snap points: every row top, plus the end so the last row sits on the bottom edge.
    local seen, snaps = { [0] = true, [self.max] = true }, { 0, self.max }
    for _, row in ipairs(rows) do
        local s = math.min(row.y, self.max)
        if row.kind ~= "sep" and not seen[s] then seen[s] = true; snaps[#snaps + 1] = s end
    end
    table.sort(snaps)
    self.snaps = snaps
end

function M:clamp(y) return math.max(0, math.min(self.max, y)) end
function M:nearestSnap(y)
    y = self:clamp(y)
    local best = 0
    for _, s in ipairs(self.snaps) do
        if math.abs(s - y) < math.abs(best - y) then best = s end
    end
    return best
end
function M:pageStep() return math.max(ROW, self.view_h - ROW) end
function M:pageCount() return self.max > 0 and math.ceil(self.max / self:pageStep()) + 1 or 1 end
function M:currentPage()
    if self.offset >= self.max then return self:pageCount() end
    return math.floor(self.offset / self:pageStep()) + 1
end
function M:depth() return self.at_root and 0 or #self.item_table_stack + 1 end
function M:padRight() return self.max > 0 and PAD_R_SCROLL or PAD_R end

-- TouchMenu:updateItems(target_page, target_item_id); offset is internal.
function M:updateItems(target_page, target_item_id, offset)
    if self.closed then return end
    local depth = self:depth()
    for d = #self.titles, depth + 1, -1 do self.titles[d] = nil; self.offsets[d] = nil end
    self:layout()
    if offset then
        self.offset = offset
    elseif target_item_id ~= nil then
        for _, row in ipairs(self.rows) do
            if row.item and row.item.menu_item_id == target_item_id then self.offset = row.y; break end
        end
    elseif target_page then
        self.offset = (target_page - 1) * self:pageStep()
    elseif self.page ~= self:currentPage() then -- a callback set touchmenu_instance.page
        self.offset = (self.page - 1) * self:pageStep()
    end
    self.offset = self:nearestSnap(self.offset)
    self.page = self:currentPage()
    self.drag = nil
    UIManager:setDirty(self, "ui", self.dimen)
end

function M:listRegion()
    local top = math.floor(VIEW_TOP * self.scale)
    return Geom:new{ x = 0, y = top, w = self.dimen.w, h = self.dimen.h - top }
end
function M:scrollTo(y)
    self:cancelPanTimer()
    self.offset = self:nearestSnap(y)
    self.page = self:currentPage()
    UIManager:setDirty(self, "ui", self:listRegion())
end
function M:scrollPage(direction)
    if self.max <= 0 then return true end
    self:scrollTo(self.offset + direction * self:pageStep())
    return true
end
function M:onNextPage() return self:scrollPage(1) end
function M:onPrevPage() return self:scrollPage(-1) end

------------------------------------------------------------------------------
-- Navigation, mirroring TouchMenu

function M:showRoot()
    self.at_root, self.item_table, self.cur_tab = true, nil, nil
    self.item_table_stack, self.path_stack = {}, {}
    self:updateItems(nil, nil, self.root_offset)
end

-- A page by its kd_key: a root section, "book" (book actions) or "search" (results).
function M:sectionPage(key)
    if self.book_page and key == "book" then return self.book_page end
    if self.search_page and key == "search" then return self.search_page end
    for _, section in ipairs(self.tab_item_table) do
        if section.kd_key == key then return section end
    end
end

-- standalone: opened straight on this page (book actions from Quick actions); Back closes.
function M:openTab(key, standalone)
    local tab = self:sectionPage(key)
    if not tab or self.closed then return end
    self:closeConfigDialog()
    if self.at_root then self.root_offset = self.offset end
    self.standalone = standalone == true
    self.at_root, self.cur_tab, self.item_table = false, key, tab
    self.item_table_stack, self.path_stack = {}, {}
    self.titles, self.offsets = { tab.text or "" }, {}
    self:updateItems(nil, nil, 0)
end

function M:pushPage(item, sub_item_table)
    local depth = self:depth()
    self.offsets[depth] = self.offset
    table.insert(self.item_table_stack, self.item_table)
    table.insert(self.path_stack, { idx = item.idx, text = Items.text(item), sub_count = #sub_item_table })
    Items.itemId(item)
    self.titles[depth + 1] = self:describe(item).label
    self.item_table = sub_item_table
    self.offset = 0
    self:updateItems(1, sub_item_table.open_on_menu_item_id_func and sub_item_table.open_on_menu_item_id_func())
end

function M:backToUpperMenu(no_close)
    if #self.item_table_stack ~= 0 then
        self.item_table = table.remove(self.item_table_stack)
        if #self.path_stack > 0 then table.remove(self.path_stack) end
        if self.item_table.needs_refresh and self.item_table.refresh_func then
            self.item_table = self.item_table.refresh_func()
        end
        self:updateItems(nil, nil, self.offsets[self:depth()] or 0)
    elseif self.standalone then
        self:closeMenu()
    elseif not self.at_root then
        self:showRoot()
    elseif not no_close then
        self:closeMenu()
    end
end
function M:onBack() self:backToUpperMenu(); return true end

-- Same hook as ReaderMenu's TouchMenu: selecting an item closes the stock bottom menu.
function M:closeConfigDialog()
    local config = self.ui.config
    if config and config.config_dialog then self.ui:handleEvent(Event:new("CloseConfigMenu")) end
end

-- Open the page and walk into each submenu of chain; stop at a leaf without running it.
function M:openChain(key, chain, standalone)
    self.popup = nil
    self:openTab(key, standalone)
    if self.closed or self.at_root then return end
    for _, wanted in ipairs(chain) do
        local item = Items.findIn(self.item_table, wanted)
        if not item then return end
        if not Items.hasSub(item) or not Items.enabled(item) then
            self:updateItems(nil, Items.itemId(item))
            return
        end
        self:onMenuSelect(item)
    end
end

-- Page key and chain of items down to key: a MenuSorter id or one of our kd_key names.
function M:findItem(key)
    local function pred(item) return item.id == key or item.kd_key == key or item.kd_view_of == key end
    local pages = {}
    for _, section in ipairs(self.tab_item_table) do pages[#pages + 1] = section end
    pages[#pages + 1] = self.book_page
    for _, page in ipairs(pages) do
        local chain = Items.findChain(page, pred, SEARCH_DEPTH)
        if chain then return page.kd_key, chain end
    end
end

function M:openItem(key)
    local page, chain = self:findItem(key)
    if page then self:openChain(page, chain) end
    return page ~= nil
end

function M:getState()
    return { tab = self.cur_tab, path_stack = self.path_stack, offset = self.offset, standalone = self.standalone }
end

-- Mirrors TouchMenu:restoreState from newer KOReader: match each path entry by
-- index and text, then by text, then by submenu size.
function M:restoreState(state)
    if not state then return end
    if state.tab and self.at_root and state.tab ~= "search" then self:openTab(state.tab, state.standalone) end
    if self.closed or self.at_root then return end
    for _, entry in ipairs(state.path_stack or {}) do
        local target, sub, candidate = nil, nil, self.item_table[entry.idx]
        if candidate and Items.text(candidate) == entry.text then target = candidate end
        if not target then
            for _, item in ipairs(self.item_table) do
                if type(item) == "table" and Items.text(item) == entry.text then target = item; break end
            end
        end
        if not target and candidate then
            sub = Items.subTable(candidate)
            if sub and #sub > 0 and entry.sub_count == #sub then target = candidate end
        end
        if not target then break end
        sub = sub or Items.subTable(target)
        if not sub or #sub == 0 then break end
        self:pushPage(target, sub)
    end
    if state.offset then self:updateItems(nil, nil, state.offset) end
end

------------------------------------------------------------------------------
-- Menu search over the new tree (KOReader's own search walks the classic one).

-- Matches of query in every page, drawer rows included: {text, path, key or drawer_tab, chain}.
function M:search(query)
    local found = {}
    local function walk(items, title, entry)
        Items.walk(items, function(item, chain)
            local ok, text = pcall(Items.text, item)
            if ok and text ~= "" and Items.lower(text):find(query, 1, true) then
                local path, copy = { title }, {}
                for i, v in ipairs(chain) do
                    copy[i] = v
                    if i < #chain then path[#path + 1] = Items.ucfirst((Items.splitLabel(Items.text(v)))) end
                end
                found[#found + 1] = { text = text, path = table.concat(path, " › "), chain = copy,
                    key = entry.key, drawer_tab = entry.drawer_tab }
            end
        end, { funcs = true, search = true, depth = SEARCH_DEPTH })
    end
    for _, section in ipairs(self.tab_item_table) do walk(section, section.text or "", { key = section.kd_key }) end
    if self.book_page then walk(self.book_page, self.book_page.text or "", { key = "book" }) end
    for _, page in ipairs(self.owner.drawerSearchPages and self.owner:drawerSearchPages() or {}) do
        walk(page.items, page.title, { drawer_tab = page.drawer_tab })
    end
    return found
end

function M:showSearchResults(query)
    local _ = require("gettext") -- luacheck: ignore 421
    local T = require("ffi/util").template
    local found = self:search(query)
    if #found == 0 then
        local InfoMessage = require("ui/widget/infomessage")
        UIManager:show(InfoMessage:new{ text = T(_("No menus containing '%1' found."), query) })
        return
    end
    local page = { kd_section = true, kd_key = "search", text = _("Search results") }
    for _, entry in ipairs(found) do
        page[#page + 1] = { text = entry.text, hint = entry.path, keep_menu_open = true,
            callback = function() self:openFound(entry) end }
    end
    self.search_page = page
    self:openTab("search")
end

function M:openFound(entry)
    if entry.drawer_tab then
        self.owner:openDrawerChain(entry.drawer_tab, entry.chain)
        return
    end
    self:openChain(entry.key, entry.chain)
end

-- KOReader's "Menu search" item sends ShowMenuSearch to the top widget.
function M:onShowMenuSearch()
    local _ = require("gettext")
    local InputDialog = require("ui/widget/inputdialog")
    local dialog
    dialog = InputDialog:new{
        title = _("Search menu entry"),
        description = _("Search for a menu entry containing the following text (case insensitive)."),
        input = G_reader_settings:readSetting("menu_search_string", _("Help")),
        buttons = {{
            { text = _("Cancel"), id = "close", callback = function() UIManager:close(dialog) end },
            { text = _("Search"), is_enter_default = true, callback = function()
                local query = Items.lower(dialog:getInputText())
                G_reader_settings:saveSetting("menu_search_string", query)
                UIManager:close(dialog)
                if not self.closed then self:showSearchResults(query) end
            end },
        }},
    }
    UIManager:show(dialog)
    if dialog.onShowKeyboard then dialog:onShowKeyboard() end
    return true
end

function M:closeMenu()
    if self.closed then return end
    if self.menu.menu_container == self then
        self.owner:closeTopMenu()
    else
        UIManager:close(self)
    end
end
function M:onClose() self:closeMenu(); return true end

------------------------------------------------------------------------------
-- Painting

function M:face(size)
    local face = self.faces[size]
    if not face then
        face = Drawer.face(size, self.scale)
        self.faces[size] = face
    end
    return face
end

function M:newText(value, size, opts)
    return TextWidget:new{ text = value, bold = opts.bold, fgcolor = opts.color, padding = 0,
        face = self:face(size), lang = self.lang, para_direction_rtl = false,
        max_width = math.max(1, math.floor((opts.max_width or self.W) * self.scale)) }
end

-- Paints widget with its vertical center at y; returns its width in units and whether it is cut.
function M:drawText(bb, widget, x, y, align)
    local size_px = widget:getSize()
    local px = x * self.scale
    if align == "right" then px = px - size_px.w elseif align == "center" then px = px - size_px.w / 2 end
    widget:paintTo(bb, math.floor(px), math.floor(y * self.scale - size_px.h / 2))
    return size_px.w / self.scale, widget:isTruncated()
end

function M:text(bb, value, x, y, size, opts)
    opts = opts or {}
    local widget = self:newText(value, size, opts)
    local w, truncated = self:drawText(bb, widget, x, y, opts.align)
    widget:free()
    return w, truncated
end

-- Row texts keep their widget until layout() replaces the rows: text, size, style
-- and width do not change in between, and panning repaints rows every PAN_MS.
function M:rowText(bb, row, key, value, x, y, size, opts)
    row.texts = row.texts or {}
    local widget = row.texts[key]
    if not widget then
        widget = self:newText(value, size, opts)
        row.texts[key] = widget
    end
    return self:drawText(bb, widget, x, y, opts.align)
end

function M:icon(bb, id, cx, cy, w, h)
    h = h or w
    local key = id .. ":" .. w .. "x" .. h
    if not self.images[key] then
        self.images[key] = ImageWidget:new{ file = icon_dir .. id .. ".svg", alpha = true, original_in_nightmode = false,
            width = math.max(1, math.floor(w * self.scale + 0.5)), height = math.max(1, math.floor(h * self.scale + 0.5)) }
    end
    self.images[key]:paintTo(bb, math.floor((cx - w / 2) * self.scale + 0.5), math.floor((cy - h / 2) * self.scale + 0.5))
end

function M:rect(bb, x, y, w, h, c)
    local px, py = math.floor(x * self.scale), math.floor(y * self.scale)
    bb:paintRect(px, py, math.max(1, math.floor((x + w) * self.scale) - px),
        math.max(1, math.floor((y + h) * self.scale) - py), c or black)
end

-- Battery as primitives so it follows night-mode inversion.
function M:paintStatus(bb)
    local W = self.W
    self:text(bb, datetime.secondsToHour(os.time(), G_reader_settings:isTrue("twelve_hour_clock")), 14, STATUS_H / 2, 12)
    self:icon(bb, "menu-handle", W / 2, 13, 44, 10)
    local power = Device:getPowerDevice()
    local right = W - 14
    if not Device.hasBattery or Device:hasBattery() then
        local capacity = Drawer.batteryCapacity(power)
        local bx, by = right - 22, STATUS_H / 2 - 5.5
        self:rect(bb, bx, by, 19.5, 11, black)
        self:rect(bb, bx + 1.5, by + 1.5, 16.5, 8, white)
        self:rect(bb, bx + 20, by + 3.5, 1.6, 4, black)
        if power:isCharging() then
            self:icon(bb, "charging", bx + 9.75, by + 5.5, 12)
        elseif capacity and capacity > 0 then
            self:rect(bb, bx + 2.6, by + 2.6, 14.3 * capacity / 100, 5.8, black)
        end
        local w = self:text(bb, capacity and (capacity .. "%") or "—", bx - 6, STATUS_H / 2, 12, { align = "right", max_width = 60 })
        right = bx - 6 - w
    end
    if Device:hasWifiToggle() and NetworkMgr:isWifiOn() then
        self:icon(bb, "menu-wifi", right - 6 - 8, STATUS_H / 2, 16, 12)
    end
end

function M:title()
    if self.at_root then return tr("Settings") end
    return self.titles[self:depth()] or self.titles[#self.titles] or ""
end

function M:paintTitle(bb)
    local W, cy = self.W, STATUS_H + TITLE_H / 2
    local x = 24
    if not self.at_root then
        self:icon(bb, "menu-back", 24, cy, 22, 18)
        x = 44
    end
    self:text(bb, self:title(), x, cy, 16, { bold = true, max_width = W - 86 - x - 8 })
    self:icon(bb, "menu-more", W - 66, cy, 4, 18)
    self:icon(bb, "menu-close", W - 26, cy, 18)
    self:rect(bb, 0, VIEW_TOP - 1, W, 1, c_border)
end

function M:paintRow(bb, row, y, next_row)
    local W = self.W
    local right = W - self:padRight()
    local mid = y + row.h / 2
    if row.kind == "sep" then
        self:rect(bb, 0, y + row.h / 2, self.max > 0 and W - SCROLLBAR_COL or W, 1, c_group)
        return
    end
    if row.kind == "caption" then
        -- Group caption as in the mockup: a rule above (not on the first one), small uppercase text.
        if row.y > 0 then self:rect(bb, 0, y + 6, self.max > 0 and W - SCROLLBAR_COL or W, 1, c_group) end
        self:rowText(bb, row, "label", row.label, PAD_L, y + row.h - 12, 11.5,
            { bold = true, color = c_sub, max_width = right - PAD_L })
        return
    end
    local label_x = PAD_L
    local enabled = row.enabled
    if row.kind == "tab" then
        self:icon(bb, row.icon, PAD_L + 12, mid, 22)
        label_x = PAD_L + 24 + 16
    elseif row.kind == "radio" then
        self:icon(bb, row.on and "menu-radio-on" or "menu-radio-off", PAD_L + 10, mid, 20)
        label_x = PAD_L + 20 + 16
    end
    local limit = right
    local value_truncated = false
    if enabled then
        if row.chevron then
            self:icon(bb, "menu-chevron", right - 4.5, mid, 9, 15)
            limit = right - CHEVRON_COL
        end
        if row.switch ~= nil then
            self:icon(bb, row.switch and "switch-on" or "switch-off", limit - 25, mid, 50)
            limit = limit - SWITCH_COL
        elseif row.value then
            local w, cut = self:rowText(bb, row, "value", row.value, limit, mid, 13.5,
                { align = "right", color = c_value, max_width = 150 })
            value_truncated = cut
            limit = limit - w - 12
        end
    end
    local label_y = row.sub and y + 25 or mid
    local bold = enabled and (row.kind ~= "radio" or row.on)
    local _, truncated = self:rowText(bb, row, "label", row.label or "", label_x, label_y, 15.5,
        { bold = bold, color = not enabled and c_disabled or nil, max_width = math.max(20, limit - label_x) })
    -- Like TouchMenu, hold shows the whole text when any part of the row is cut.
    row.truncated = truncated or value_truncated
    if row.sub then
        -- Label and subtitle share the column left of the value, as in the mockup.
        self:rowText(bb, row, "sub", row.sub, label_x, y + 46, 12.5, { color = c_sub, max_width = math.max(20, limit - label_x) })
    end
    if not (next_row and (next_row.kind == "sep" or next_row.kind == "caption")) then
        self:rect(bb, PAD_L, y + row.h - 1, right - PAD_L, 1, c_divider)
    end
end

function M:scrollbar()
    if self.max <= 0 then return nil end
    local top, bottom = VIEW_TOP + 6, self.H - 8
    local track_top, track_bottom = top + 20, bottom - 20
    local track_h = track_bottom - track_top
    local thumb_h = math.max(24, track_h * self.view_h / self.total)
    return { x = self.W - 21, top = top, bottom = bottom, track_top = track_top, track_h = track_h,
        thumb_top = track_top + (self.offset / self.max) * (track_h - thumb_h), thumb_h = thumb_h }
end

function M:paintScrollbar(bb, bar)
    self:icon(bb, self.offset <= 0 and "menu-up-off" or "menu-up", bar.x, bar.top + 9, 14, 18)
    self:icon(bb, self.offset >= self.max and "menu-down-off" or "menu-down", bar.x, bar.bottom - 9, 14, 18)
    self:rect(bb, bar.x - 1, bar.track_top, 2, bar.track_h, c_divider)
    self:rect(bb, bar.x - 2, bar.thumb_top, 4, bar.thumb_h, black)
end

-- ⋮ menu: book actions (in a book), the classic KOReader menu, the plugin's settings.
function M:popupItems()
    local items = {}
    if self.book_page then items[#items + 1] = { id = "book", text = tr("Book actions") } end
    items[#items + 1] = { id = "classic", text = tr("Classic KOReader menu") }
    items[#items + 1] = { id = "plugin", text = tr("Kindle Drawer settings") }
    return items
end
function M:popupRect()
    return { x = self.W - 8 - POP_W, y = 70, w = POP_W, h = #self:popupItems() * POP_ITEM }
end
function M:paintPopup(bb)
    local p = self:popupRect()
    self:rect(bb, p.x, p.y, p.w, p.h, black)
    self:rect(bb, p.x + 1.5, p.y + 1.5, p.w - 3, p.h - 3, white)
    for i, item in ipairs(self:popupItems()) do
        local top = p.y + (i - 1) * POP_ITEM
        if i > 1 then self:rect(bb, p.x + 1.5, top, p.w - 3, 1, c_divider) end
        self:text(bb, item.text, p.x + 16, top + POP_ITEM / 2, 14.5, { max_width = p.w - 32 })
    end
end

function M:paintTo(bb, x, y)
    self.dimen.x, self.dimen.y = x or 0, y or 0
    bb:paintRect(0, 0, self.dimen.w, self.dimen.h, white)
    -- List first; the header painted afterwards hides rows scrolled above the viewport.
    for i, row in ipairs(self.rows) do
        local ry = VIEW_TOP + row.y - self.offset
        if ry + row.h > VIEW_TOP and ry < self.H then self:paintRow(bb, row, ry, self.rows[i + 1]) end
    end
    bb:paintRect(0, 0, self.dimen.w, math.floor(VIEW_TOP * self.scale), white)
    self:paintStatus(bb)
    self:paintTitle(bb)
    local bar = self:scrollbar()
    if bar then self:paintScrollbar(bb, bar) end
    if self.popup then self:paintPopup(bb) end
end

------------------------------------------------------------------------------
-- Input

function M:rowAt(uy)
    local y = uy - VIEW_TOP + self.offset
    for _, row in ipairs(self.rows) do
        if y >= row.y and y < row.y + row.h then return row end
    end
end

function M:closePopup()
    self.popup = nil
    UIManager:setDirty(self, "ui", self.dimen)
end

function M:popupTap(ux, uy)
    local p = self:popupRect()
    if ux < p.x or ux > p.x + p.w or uy < p.y or uy > p.y + p.h then
        self:closePopup()
        return true
    end
    self.popup = nil
    local item = self:popupItems()[math.max(1, math.min(#self:popupItems(), math.floor((uy - p.y) / POP_ITEM) + 1))]
    if item.id == "classic" then
        self.owner:showClassicMenu()
        return true
    elseif item.id == "book" then
        self:openTab("book")
    else
        self.owner:openMenuItem("kindle_drawer")
    end
    if not self.closed then UIManager:setDirty(self, "ui", self.dimen) end
    return true
end

function M:onKMenu_tap(_, ges)
    local ux, uy = ges.pos.x / self.scale, ges.pos.y / self.scale
    if self.popup then return self:popupTap(ux, uy) end
    local W = self.W
    if uy < STATUS_H then
        if math.abs(ux - W / 2) <= 40 then self.owner:onKindleDrawer() end
        return true
    end
    if uy < VIEW_TOP then
        if ux < 48 and not self.at_root then self:backToUpperMenu(true)
        elseif ux >= W - 86 and ux < W - 46 then
            self.popup = true
            UIManager:setDirty(self, "ui", self.dimen)
        elseif ux >= W - 46 then self:closeMenu() end
        return true
    end
    local bar = self:scrollbar()
    if bar and ux >= W - SCROLLBAR_COL then
        if uy < bar.track_top then self:scrollPage(-1)
        elseif uy > bar.track_top + bar.track_h then self:scrollPage(1)
        else self:scrollPage(uy < bar.thumb_top and -1 or 1) end
        return true
    end
    local row = self:rowAt(uy)
    if not row or row.kind == "sep" or row.kind == "caption" then return true end
    -- TouchMenu re-evaluates enabled_func at tap time; the row cache may be stale.
    if row.item and not Items.enabled(row.item) then return true end
    if row.kind == "tab" then
        self:openTab(row.key)
        return true
    end
    -- Only the switch itself is the checkmark; a chevron next to it opens the submenu.
    local switch_right = W - self:padRight() - (row.chevron and CHEVRON_COL or 0)
    local on_switch = row.switch ~= nil and ux >= switch_right - SWITCH_COL and (not row.chevron or ux < switch_right)
    self:onMenuSelect(row.item, on_switch)
    return true
end

function M:onKMenu_hold(_, ges)
    if self.popup then self:closePopup(); return true end
    local uy = ges.pos.y / self.scale
    if uy < VIEW_TOP then return true end
    local row = self:rowAt(uy)
    if not row or not row.item then return true end
    -- TouchMenu shows help for disabled items but runs nothing else.
    if not Items.enabled(row.item) then self:showHelp(row.item) return true end
    self:onMenuHold(row.item, row.truncated)
    return true
end

function M:cancelPanTimer()
    if self.pan_timer then UIManager:unschedule(self.pan_timer); self.pan_timer = nil end
end

-- E-ink: fast refresh of the list region only, at most every PAN_MS.
function M:panRepaint()
    local now = self:now()
    if not self.last_pan_paint or now - self.last_pan_paint >= PAN_MS then
        self.last_pan_paint, self.pan_painted = now, self.offset
        UIManager:setDirty(self, "fast", self:listRegion())
    elseif not self.pan_timer then
        self.pan_timer = function()
            self.pan_timer = nil
            if self.drag and self.offset ~= self.pan_painted then self:panRepaint() end
        end
        UIManager:scheduleIn((PAN_MS - (now - self.last_pan_paint)) / 1000, self.pan_timer)
    end
end

function M:onKMenu_pan(_, ges)
    if self.popup then return true end
    if self.drag == nil then
        local start = ges.start_pos or ges.pos
        local rel = ges.relative
        local vertical = rel and math.abs(rel.y) >= math.abs(rel.x)
            or (ges.direction == "north" or ges.direction == "south")
        if start and start.y / self.scale >= VIEW_TOP and self.max > 0 and vertical then
            self.drag = { start_y = start.y, offset = self.offset, samples = {} }
        else
            self.drag = false
        end
    end
    local drag = self.drag
    if drag then
        self.offset = self:clamp(drag.offset - (ges.pos.y - drag.start_y) / self.scale)
        local t = self:now(ges)
        drag.samples[#drag.samples + 1] = { t = t, y = ges.pos.y }
        while #drag.samples > 2 and t - drag.samples[1].t > 100 do table.remove(drag.samples, 1) end
        self:panRepaint()
    end
    return true
end

-- Settle the drag in progress at finger position y (screen px, may be nil):
-- momentum from the last samples, then snap. Returns false when there was none.
function M:endDrag(ges, y)
    local drag = self.drag
    self.drag = nil
    if not drag then return false end
    local t = self:now(ges)
    if y then self.offset = self:clamp(drag.offset - (y - drag.start_y) / self.scale) end
    local a, b = drag.samples[1], drag.samples[#drag.samples]
    local v = 0 -- units per ms
    if a and b and b.t > a.t and t - b.t < PAN_MS then v = (b.y - a.y) / (b.t - a.t) / self.scale end
    local fling = math.abs(v) > 0.4 and -v * FLING_MS or 0
    self.last_pan_paint = nil
    self:scrollTo(self.offset + fling)
    return true
end

function M:onKMenu_pan_release(_, ges)
    self:endDrag(ges, ges.pos and ges.pos.y)
    return true
end

function M:onKMenu_swipe(_, ges)
    if self.popup then self.drag = nil; self:closePopup(); return true end
    -- Fast drags end as swipe instead of pan_release.
    if self:endDrag(ges, ges.end_pos and ges.end_pos.y) then return true end
    local start = ges.pos
    if start.y / self.scale < VIEW_TOP then
        if ges.direction == "south" and self.owner.settings.enabled ~= false then self.owner:onKindleDrawer()
        elseif ges.direction == "north" then self:closeMenu() end
        return true
    end
    if ges.direction == "east" then
        self:backToUpperMenu(true)
    elseif (ges.direction == "north" or ges.direction == "south") and self.max > 0 then
        -- A flick without pan events: no samples, assume a typical 150 ms stroke.
        local travel = ges.end_pos and (ges.end_pos.y - start.y) / self.scale
            or (ges.direction == "north" and -1 or 1) * (ges.distance or 0) / self.scale
        self:scrollTo(self.offset - travel - travel / 150 * FLING_MS)
    end
    return true
end

-- A drag that turns ends as multiswipe: settle it like a release.
function M:onKMenu_multiswipe(_, ges)
    self:endDrag(ges, ges and ges.end_pos and ges.end_pos.y)
    return true
end

-- Mouse wheel in the SDL emulator arrives as a Pan event (TouchMenu:onPan).
function M:onPan(_, ges)
    if ges and ges.mousewheel_direction and self.max > 0 and not self.popup then
        self:scrollTo(self.offset + (ges.direction == "north" and 1 or -1) * WHEEL_ROWS * ROW)
    end
    return true
end

function M:onCloseWidget()
    if self.closed then return end
    self.closed = true
    self:cancelPanTimer()
    for _, image in pairs(self.images) do image:free() end
    self.images = {}
    freeRowTexts(self.rows)
    if self.owner.settings_menu == self then self.owner.settings_menu = nil end
    if self.menu.menu_container == self then self.menu.menu_container = nil end
    -- Like TouchMenu: no flash when the UI underneath is being torn down.
    if not self.ui.tearing_down then UIManager:setDirty(nil, self.full_refresh and "full" or "flashui") end
end

return M
