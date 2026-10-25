-- New arrangement of KOReader's top menu (design/settings-reorg.html).
-- Rows reference KOReader items by MenuSorter id and show KOReader's own item
-- tables; only sections, captions and new grouping containers have our strings.
-- Children without an id are shown through views (shallow copies), so the
-- classic tree that MenuSorter built stays untouched.
local Items = require("menuitems")
local logger = require("logger")
local gettext = require("gettext")
local tr = require("l10n").tr

local L = {}

local function H(caption) return { caption = caption } end
-- A child of a KOReader item without its own id: tried at pos first, always checked by text.
-- copy = true keeps it in its parent as well.
local function X(parent, msgids, pos, copy) return { extract = parent, match = msgids, pos = pos, copy = copy } end

local FULL_REFRESH = X("screen_eink_opt", { "Full refresh rate" }, 1)
local ANTI_GHOSTING = X("screen_eink_opt", { "Sleep screen anti-ghosting redraws: off",
    "Sleep screen anti-ghosting redraws: %1×, %2 ms" })
local NO_COVER = X("screensaver", { "Do not show this book cover on sleep screen" })
local HISTORY_SETTINGS = X("filebrowser_settings", { "History settings" }, 5)
local HOME_FOLDER = X("filebrowser_settings", { "Home folder settings" }, 6)
local FONT_SETTINGS = X("change_font", { "Font settings" }, 1)
local FONT_FAMILY = X("change_font", { "Font-family fonts", "Font-family fonts (%1)" }, 2)
local PUSH_PROGRESS = X("progress_sync", { "Push progress from this device now" }, nil, true)
local PULL_PROGRESS = X("progress_sync", { "Pull progress from other devices now" }, nil, true)

L.SECTIONS = {
    { key = "network", title = "Wi-Fi & network", icon = "section-network", hint = "Wi-Fi, proxy, file transfer",
        "network_wifi", { special = "wifi_networks" }, "network_before_wifi_action", "network_after_wifi_action",
        "network_restore", "network_powersave", "network_dismiss_scan", "network_proxy", "network_info",
        H("File transfer and remote access"), "calibre", "localsend", "ssh",
    },
    { key = "screen", title = "Screen & light", icon = "section-screen", hint = "Frontlight, dark mode, lock screen, rotation",
        "frontlight", "auto_frontlight", "night_mode", "autowarmth", "autodim",
        H("Lock screen"), { id = "screensaver", add = { ANTI_GHOSTING } }, "coverimage",
        H("Display"), "screen_rotation", "screen_dpi", "color_rendering", "fullscreen", "screen_timeout", "screen_eink_opt",
    },
    { key = "power", title = "Power & battery", icon = "section-power", hint = "Auto-sleep, power-off, cover, alerts",
        "autosuspend", "autoshutdown", "autostandby", "keep_alive",
        H("Cover and buttons"), "cover_events", "ignore_sleepcover", "ignore_open_sleepcover", "pageturn_power",
        "charging_led", "ignore_battery_optimizations",
        H("Status"), "device_status_alarm", "battery_statistics",
    },
    { key = "gestures", title = "Gestures & buttons", icon = "section-gestures", hint = "Gestures, menu activation, Back and page-turn buttons",
        "gesture_manager", "gesture_overview", "gesture_intervals", "ignore_hold_corners", "screen_disable_double_tap", "menu_activate",
        H("Buttons"),
        { group = "back_button", label = "Back button", rows = { "back_to_exit", "back_in_filemanager", "back_in_reader",
            "backspace_as_back", "android_back_button" } },
        "physical_buttons_setup", "android_volume_keys", "android_haptic_feedback",
    },
    { key = "language", title = "Language & dictionaries", icon = "section-language", hint = "Language, keyboard, dictionaries, Wikipedia, translation",
        "language", "keyboard_layout", "external_keyboard", "font_ui_fallbacks", "language_support",
        H("Dictionaries"), "dictionary_lookup", "dictionary_lookup_history", "vocabbuilder", "dictionary_settings",
        H("Wikipedia and translation"), "wikipedia_lookup", "wikipedia_history", "wikipedia_settings", "translation_settings",
    },
    { key = "library", title = "Library", icon = "section-library", hint = "List view, sorting, history, metadata",
        H("Open"), { id = "filemanager", label = "File browser" }, { id = "reader", label = "Continue reading" },
        { id = "plus_menu", label = "Plus menu" }, "history", "favorites", "collections", "bookmark_browser",
        "open_last_document", "open_previous_document", "file_search", "file_search_results",
        "find_book_in_calibre_catalog", "opds",
        H("View and sorting"), { id = "filemanager_display_mode", label = "View", radio_label = "Library view" },
        "sort_by", "reverse_sorting", "sort_ignore_articles", "sort_mixed", "show_filter", "filebrowser_settings",
        H("Startup and folders"), "start_with", "simpleui", HOME_FOLDER, "book_shortcuts", HISTORY_SETTINGS, "move_to_archive",
        H("Book data"), "document_metadata_location", "document_metadata_location_move", "document_auto_save",
        "document_metadata_arc", "doc_setting_tweak", "file_ext_assoc",
    },
    { key = "reading", title = "Reading", icon = "section-reading", hint = "Page refresh, end of book, statistics, sync",
        FULL_REFRESH, { id = "document_end_action", label = "End of book", radio_label = "Action" },
        "opening_page_location_stack", "skim_dialog_position",
        H("Progress and notes"), "statistics", "read_timer", "progress_sync", "exporter",
        { slot = "drawer" },
    },
    { key = "apps", title = "Apps & plugins", icon = "section-apps", hint = "Tools, services, plugin management",
        "cloudstorage", "cloud_storage", "wallabag", "news_downloader", "text_editor", "profiles", "qrclipboard",
        "terminal", "kindle_drawer",
        H("Other plugins"), { slot = "other" },
        H("Management"), "plugin_management", "patch_management", "plugins_disable_external",
    },
    { key = "device", title = "Device", icon = "section-device", hint = "Date and time, storage, updates, restart",
        { id = "time", label = "Date and time", add = { "synchronize_time" } }, "units", "screen_notification", "screenshot",
        { group = "usb_storage", label = "USB storage", rows = { "mass_storage_actions", "mass_storage_settings" } },
        "ota_update",
        H("Restart"), "restart_koreader", "sleep", "reboot", "poweroff", "start_bq", "exit", { id = "exit_menu", if_leaf = true },
        H("Advanced"), "advanced_settings", "developer_options", "httpremote",
    },
    { key = "help", title = "Help", icon = "section-help", hint = "Guide, menu search, version",
        "quickstart_guide", "search_menu", "report_bug", "system_statistics", "version", "about",
    },
}

-- Book actions: ⋮ in Quick actions panel and "Book actions" in the settings ⋮.
L.BOOK = { key = "book", title = "Book actions",
    "table_of_contents", "bookmarks", "toggle_bookmark", "bookmark_browsing_mode", "book_map", "page_browser",
    "go_to", "skim_to", "go_to_previous_location", "go_to_next_location",
    H("Search"), "fulltext_search", "fulltext_search_findall_results", "bookmark_search", "translate_current_page",
    H("Book"), "book_status", NO_COVER, PUSH_PROGRESS, PULL_PROGRESS, "book_info", "start_content_selection",
}

-- Drawer rows by key. A key without an entry here is the MenuSorter id itself.
L.DRAWER_ROWS = {
    font_family = FONT_FAMILY, font_settings = FONT_SETTINGS,
    links = { first = { "follow_links", "typesetfootnotes" } },
}
local function drawerSpec(key) return L.DRAWER_ROWS[key] or key end

-- Drawer tabs. opts: ReaderConfig panels by icon ("*" takes every option left over);
-- opt: one ReaderConfig option moved here; row: a drawer row key.
local READING = { key = "reading", title = "Reading", { caption = "For all books" },
    { row = "page_turns" }, { row = "scrolling" }, { row = "links" }, { row = "long_press" },
    { row = "highlight_options" }, { row = "selection_text" }, { row = "autoturn" },
    { row = "speed_reading_module_perception_expander" }, { row = "fulltext_search_settings" } }
local MORE = { key = "more", title = "More", { opts = "*" }, { caption = "Contents and bookmarks" },
    { row = "navi_settings" }, { row = "bookmarks_settings" }, { caption = "Document" },
    { row = "document_settings" }, { row = "partial_rerendering" }, { row = "panel_zoom_options" },
    { row = "djvu_render_mode" } }
local PAGE_ROWS = { { row = "page_overlap" }, { row = "page_map" }, { row = "hide_nonlinear_flows" }, { row = "switch_zoom_mode" } }
local function page(opts, extra)
    local tab = { key = "page", title = "Page", { opts = opts }, { caption = "Status bar and pages" }, { row = "status_bar" } }
    for _, v in ipairs(extra) do tab[#tab + 1] = v end
    for _, v in ipairs(PAGE_ROWS) do tab[#tab + 1] = v end
    return tab
end
L.DRAWER_TABS = {
    rolling = {
        { key = "font", title = "Font", { row = "change_font" },
            { opts = { "appbar.textsize", "appbar.contrast" }, sort = "font" }, { opt = "embedded_fonts" },
            { caption = "Fonts and typography" }, { row = "font_family" }, { row = "typography" }, { row = "font_settings" } },
        { key = "layout", title = "Layout", { opts = { "appbar.rotation", "appbar.crop" } }, { caption = "Book styles" },
            { row = "set_render_style" }, { opt = "embedded_css" }, { row = "style_tweaks" } },
        page({ "appbar.pageview" }, { { opt = "status_line" } }),
        READING,
        MORE,
    },
    paging = {
        { key = "image", title = "Image", { opts = { "appbar.contrast" } }, { opt = "text_wrap" },
            { caption = "When reflowing" }, { opts = { "appbar.textsize" } }, { opt = "line_spacing" },
            { opt = "justification" }, { opt = "quality" } },
        { key = "layout", title = "Layout", { opts = { "appbar.rotation", "appbar.crop" } } },
        page({ "appbar.pageview", "appbar.pagefit" }, {}),
        READING,
        MORE,
    },
}

--[[ MenuSorter containers. route: where an unknown key hinting at the container
goes ("other" is Other plugins in Apps & plugins); dissolve: its children are
placed one by one and the container itself is not shown. ]]
L.CONTAINERS = {
    network = { route = "network", dissolve = true }, screen = { route = "screen", dissolve = true },
    device = { route = "device", dissolve = true }, exit_menu = { route = "device", dissolve = true },
    navigation = { route = "gestures", dissolve = true }, taps_and_gestures = { route = "gestures", dissolve = true },
    document = { route = "library", dissolve = true }, more_tools = { route = "other", dissolve = true },
    search_settings = { route = "other", dissolve = true }, help = { route = "other", dissolve = true },
    screensaver = { route = "screen" }, physical_buttons_setup = { route = "gestures" },
    filemanager_settings = { route = "library" }, setting = { route = "other" }, tools = { route = "other" },
    search = { route = "other" }, main = { route = "other" }, navi = { route = "other" }, typeset = { route = "other" },
    selection_text = { route = "other" },
}
-- Pages that take routed items at their end; a route to any other page means Other plugins.
L.ROUTED_PAGES = { network = true, screen = true, power = true, gestures = true, language = true,
    library = true, reading = true, device = true, help = true }

-- KOReader tab id -> section, for onShowMenu(tab_index).
L.TAB_SECTIONS = { filemanager_settings = "library", tools = "apps", search = "language", navi = "book" }

------------------------------------------------------------------------------
-- MenuSorter guard: a snapshot of the menu items before sorting, and no crash
-- on a sorting_hint that names a missing item (menusorter.lua:179-182).

local guard = { count = 0 }

function L.guardedSort(original, sorter, item_table, order)
    local snap = { items = {}, hints = {}, disabled = {}, bad_hints = {} }
    for key, item in pairs(item_table) do
        if key ~= "KOMenu:menu_buttons" and type(item) == "table" then
            snap.items[key], snap.hints[key] = item, item.sorting_hint
        end
    end
    for _, key in ipairs(order and order["KOMenu:disabled"] or {}) do snap.disabled[key] = true end
    local own = rawget(sorter, "findById")
    local find = sorter.findById
    -- Relies on menusorter.lua removing "KOMenu:menu_buttons" from item_table right
    -- before its orphan loop: only lookups after that (sorting hints) get a fallback,
    -- the submenu lookups before it stay exact.
    sorter.findById = function(s, tbl, needle)
        local found = find(s, tbl, needle)
        if found ~= nil or item_table["KOMenu:menu_buttons"] ~= nil then return found end
        snap.bad_hints[needle] = true
        return find(s, tbl, "more_tools") or find(s, tbl, "tools") or tbl[1]
    end
    local ok, result = pcall(original, sorter, item_table, order)
    sorter.findById = own
    if not ok then error(result, 0) end
    for key, hint in pairs(snap.hints) do
        if snap.bad_hints[hint] then
            logger.warn("Kindle Drawer: menu item", key, "has unknown sorting_hint", hint, "- placed in More tools")
        end
    end
    -- On the tree itself: it lives exactly as long as the tree. TouchMenu only reads its array part.
    if type(result) == "table" then result.kd_snapshot = snap end
    return result
end

function L.installSortGuard()
    local ok, MenuSorter = pcall(require, "ui/menusorter")
    if not ok or type(MenuSorter) ~= "table" or type(MenuSorter.sort) ~= "function" then return false end
    guard.count = guard.count + 1
    if guard.wrapper then return true end
    guard.module, guard.original = MenuSorter, MenuSorter.sort
    guard.wrapper = function(sorter, item_table, order)
        return L.guardedSort(guard.original, sorter, item_table, order)
    end
    MenuSorter.sort = guard.wrapper
    return true
end

function L.uninstallSortGuard()
    if guard.count == 0 then return end
    guard.count = guard.count - 1
    if guard.count == 0 and guard.wrapper then
        if guard.module.sort == guard.wrapper then guard.module.sort = guard.original end
        guard.wrapper, guard.module, guard.original = nil, nil, nil
    end
end

function L.snapshotFor(tree) return type(tree) == "table" and rawget(tree, "kd_snapshot") or nil end

------------------------------------------------------------------------------
-- Specs and matching

local function copyKeys(from, to)
    for k, v in pairs(from) do
        if type(k) ~= "number" then to[k] = v end
    end
    return to
end

-- fn(spec) for every row spec in lists, nested group rows and additions included.
local function visitSpecs(lists, fn)
    local function visit(spec)
        if type(spec) == "table" then
            for _, s in ipairs(spec.rows or {}) do visit(s) end
            for _, s in ipairs(spec.add or {}) do visit(s) end
        end
        fn(spec)
    end
    for _, list in ipairs(lists) do
        for _, spec in ipairs(list) do visit(spec) end
    end
end

local function drawerSpecs(kind)
    local specs = {}
    for _, tab in ipairs(L.DRAWER_TABS[kind]) do
        for _, seg in ipairs(tab) do if seg.row then specs[#specs + 1] = drawerSpec(seg.row) end end
    end
    return specs
end

-- Every id the layout names in any context; one of them without a place is a safety-net case.
local all_known
function L.knownIds()
    if all_known then return all_known end
    all_known = {}
    local lists = { L.BOOK, drawerSpecs("rolling"), drawerSpecs("paging") }
    for _, section in ipairs(L.SECTIONS) do lists[#lists + 1] = section end
    visitSpecs(lists, function(spec)
        if type(spec) == "string" then all_known[spec] = true return end
        if spec.id then all_known[spec.id] = true end
        for _, key in ipairs(spec.first or {}) do all_known[key] = true end
    end)
    return all_known
end

local function matches(spec, child)
    if type(child) ~= "table" then return false end
    local ok, text = pcall(Items.text, child)
    if not ok then return false end
    for _, msgid in ipairs(spec.match) do
        local s = gettext(msgid)
        if text == s then return true end
        local prefix = msgid:find("%1", 1, true) and s:match("^(.-)%s*[:(]?%s*%%1")
        if prefix and prefix ~= "" and text:sub(1, #prefix) == prefix then return true end
    end
    return false
end

local function findChild(spec, children)
    local child = spec.pos and children[spec.pos]
    if matches(spec, child) then return child end
    for _, c in ipairs(children) do if matches(spec, c) then return c end end
end

-- Extracted child of a sub_item_table_func parent: resolved when read, never at build time.
-- kd_missing is true while the parent has no such child.
local function lazyChild(spec, fn)
    local last_list, last_child
    local function resolve()
        local ok, list = pcall(fn)
        if not ok or type(list) ~= "table" then return nil end
        if list ~= last_list then last_list, last_child = list, findChild(spec, list) end
        return last_child
    end
    return setmetatable({ kd_lazy = true }, { __index = function(_, k)
        if k == "kd_missing" then return resolve() == nil end
        if type(k) == "string" and k:sub(1, 3) == "kd_" then return nil end -- our markers never resolve
        local child = resolve()
        return child and child[k]
    end })
end

-- Shallow copy of a children list without some entries, with others appended.
local function transformList(list, drop, extra)
    local out = copyKeys(list, {})
    for _, child in ipairs(list) do
        if not drop(child) then out[#out + 1] = child end
    end
    for _, child in ipairs(extra or {}) do out[#out + 1] = child end
    if type(list.refresh_func) == "function" then
        out.refresh_func = function() return transformList(list.refresh_func(), drop, extra) end
    end
    return out
end

-- Radio children move into their own page; the parent shows the selected one.
local function splitRadio(list, label, parent)
    local radios, rest, at = {}, copyKeys(list, {}), nil
    for _, child in ipairs(list) do
        if type(child) == "table" and child.radio then
            radios[#radios + 1] = child
            at = at or #rest + 1
        else
            rest[#rest + 1] = child
        end
    end
    if #radios == 0 then return list end
    table.insert(rest, at, { text = tr(label), sub_item_table = radios, kd_key = "radio_page" })
    parent.mandatory_func = function() return Items.radioValue(radios) end
    return rest
end

------------------------------------------------------------------------------
-- Builder

local B = {}
B.__index = B

function B:node(key)
    if key == nil or self.disabled[key] then return nil end
    local node = self.index[key]
    if node then return node end
    local item = self.items[key]
    if item and self.in_tree[item] then return item end
end

function B:indexTree()
    local index, in_tree, parent = {}, {}, {}
    local function walk(list, parent_id, depth)
        if depth > 12 then return end
        for _, item in ipairs(list) do
            if type(item) == "table" and not in_tree[item] then
                in_tree[item] = true
                if item.id and index[item.id] == nil then index[item.id] = item; parent[item.id] = parent_id end
                local sub = item.sub_item_table
                if type(sub) == "table" then
                    in_tree[sub] = true
                    walk(sub, item.id or parent_id, depth + 1)
                end
            end
        end
    end
    for _, tab in ipairs(self.tree) do
        if type(tab) == "table" then
            in_tree[tab] = true
            if tab.id and index[tab.id] == nil then index[tab.id] = tab end
            self.tabs[tab] = true
            walk(tab, tab.id, 1)
        end
    end
    self.index, self.in_tree, self.parent = index, in_tree, parent
end

function B:firstOf(spec)
    for _, id in ipairs(spec.first) do if self:node(id) then return id end end
end

-- Explicitly placed nodes, and the children to extract: static parents now,
-- sub_item_table_func parents lazily.
function B:prepare(lists)
    self.explicit, self.found = {}, {}
    visitSpecs(lists, function(spec)
        local id = type(spec) == "string" and spec or spec.id
        if type(spec) == "table" and spec.first then id = self:firstOf(spec) end
        if id then
            local node = self:node(id)
            if node then self.explicit[node] = id end
        elseif type(spec) == "table" and spec.extract and not self.found[spec] then
            local parent = self:node(spec.extract)
            if parent and type(parent.sub_item_table) == "table" then
                self.found[spec] = findChild(spec, parent.sub_item_table)
            elseif parent and parent.sub_item_table_func then
                self.found[spec] = lazyChild(spec, parent.sub_item_table_func)
            end
        end
    end)
end

function B:place(key, item)
    if key then
        self.placed[key] = true
        if self.counts then self.counts[key] = (self.counts[key] or 0) + 1 end
        if self.section_key and self.row_section[key] == nil then self.row_section[key] = self.section_key end
    end
    return item
end

-- The item to show for a KOReader node: the node itself, or a view when its
-- label, children or "NEW: " prefix differ.
function B:present(key, node, spec)
    spec = spec or {}
    local extracted = {}
    for s, child in pairs(self.found) do
        if s.extract == key and not s.copy then extracted[#extracted + 1] = { spec = s, child = child } end
    end
    local explicit = self.explicit
    local function drop(child)
        if type(child) ~= "table" then return false end
        for _, e in ipairs(extracted) do
            if child == e.child or matches(e.spec, child) then return true end
        end
        return explicit[child] ~= nil and child ~= node
    end
    local extra
    if spec.add then
        extra = {}
        for _, s in ipairs(spec.add) do self:make(s, extra) end
    end
    local static = type(node.sub_item_table) == "table" and node.sub_item_table
    local changes_children = #extracted > 0 or (extra and #extra > 0) or spec.radio_label
    if static and not changes_children then
        for _, child in ipairs(static) do if drop(child) then changes_children = true; break end end
    end
    local prefix = self.prefix
    local text = type(node.text) == "string" and node.text
    local strip = node.new and prefix and text and text:sub(1, #prefix) == prefix
    if not (changes_children or spec.label or strip) then return self:place(key, node) end

    local view = copyKeys(node, {})
    view.kd_view_of, view.menu_item_id, view.idx = key, nil, nil
    if spec.label then view.text, view.text_func = tr(spec.label), nil
    elseif strip then view.text = text:sub(#prefix + 1) end
    if changes_children then
        local radio_label = spec.radio_label
        local function children(list)
            local out = transformList(list, drop, extra)
            if radio_label then out = splitRadio(out, radio_label, view) end
            return out
        end
        if static then
            view.sub_item_table = children(static)
        elseif node.sub_item_table_func then
            local fn = node.sub_item_table_func
            view.sub_item_table_func = function() return children(fn()) end
        elseif extra and #extra > 0 then
            view.sub_item_table = extra
        end
    end
    return self:place(key, view)
end

function B:make(spec, out)
    if type(spec) == "string" then spec = { id = spec } end
    if spec.caption then out[#out + 1] = { kd_caption = tr(spec.caption) } return end
    if spec.slot then out[#out + 1] = { kd_slot = spec.slot } return end
    if spec.special == "wifi_networks" then
        local show = self.ctx.show_networks
        if show and self:node("network_wifi") then
            out[#out + 1] = { text = tr("Wi-Fi networks"), hint = "Network list and connection", keep_menu_open = true,
                kd_key = "wifi_networks", callback = function() show() end }
        end
        return
    end
    if spec.extract then
        out[#out + 1] = self.found[spec]
        return
    end
    if spec.group then
        local rows = {}
        for _, s in ipairs(spec.rows) do self:make(s, rows) end
        if #rows > 0 then out[#out + 1] = { text = tr(spec.label), sub_item_table = rows, kd_key = spec.group } end
        return
    end
    local id = spec.first and self:firstOf(spec) or spec.id
    local node = self:node(id)
    if not node then
        for _, s in ipairs(spec.add or {}) do self:make(s, out) end
        return
    end
    if spec.if_leaf and Items.hasSub(node) then return end
    out[#out + 1] = self:present(id, node, spec)
end

function B:section(spec, key)
    self.section_key = key
    local page = { kd_section = true, kd_key = key, text = tr(spec.title), kd_icon = spec.icon,
        kd_hint = spec.hint and tr(spec.hint) }
    for _, s in ipairs(spec) do self:make(s, page) end
    self.section_key = nil
    return page
end

-- Drawer tabs with their menu rows resolved: {key, title, segments}; a segment is
-- {caption}, {item, row}, or a ReaderConfig {opt}/{opts} for the drawer to expand.
function B:drawerTabs(kind)
    self.section_key = "drawer"
    local tabs = {}
    for _, spec in ipairs(L.DRAWER_TABS[kind]) do
        local tab = { key = spec.key, title = tr(spec.title) }
        for _, seg in ipairs(spec) do
            if seg.caption then
                tab[#tab + 1] = { caption = tr(seg.caption) }
            elseif seg.row then
                local out = {}
                self:make(drawerSpec(seg.row), out)
                if out[1] then tab[#tab + 1] = { item = out[1], row = seg.row } end
            else
                tab[#tab + 1] = seg
            end
        end
        tabs[#tabs + 1] = tab
    end
    self.section_key = nil
    return tabs
end

-- Walk everything we show; anything reachable through a kept submenu counts as placed.
function B:claim(list, depth)
    if depth > 12 or type(list) ~= "table" then return end
    for _, item in ipairs(list) do
        if type(item) == "table" and not self.claimed[item] then
            self.claimed[item] = true
            if not rawget(item, "kd_lazy") and type(item.sub_item_table) == "table" then
                self:claim(item.sub_item_table, depth + 1)
            end
        end
    end
end

-- Where an unknown key with this sorting_hint goes: the page of the nearest container
-- or placed row named by the hint or its classic ancestors. A hint on a placed item
-- without a submenu, and a page that takes no routed items, mean Other plugins.
function B:routeHint(hint)
    local h, first = hint, true
    while h do
        local container = L.CONTAINERS[h]
        local target = container and container.route or self.row_section[h]
        if target then
            if not container and first and not Items.hasSub(self:node(h) or {}) then return "other" end
            return L.ROUTED_PAGES[target] and target or "other"
        end
        h, first = self.parent[h], false
    end
    return "other"
end

function B:note(list, key, value)
    local report = self.report
    if not report then return end
    if value ~= nil then report[list][key] = value else table.insert(report[list], key) end
end

-- One snapshot key the layout did not place: inside a kept submenu, disabled,
-- a dissolved container, or routed (by rule, or by the safety net for known ids).
function B:routeKey(key, known, routed)
    local item, node = self.items[key], self:node(key)
    local container = L.CONTAINERS[key]
    if self.disabled[key] then
        self:note("disabled", key)
    elseif self.claimed[item] or (node and self.claimed[node]) then
        self:note("inside", key)
        self:place(key)
    elseif node and (self.tabs[node] or (container and container.dissolve and Items.hasSub(node))) then
        self:note("dissolved", key)
    else
        local target = "other"
        if known[key] then
            self:note("net", key)
            logger.warn("Kindle Drawer: menu item", key, "had no place in the new menu; shown in Other plugins")
        else
            local hint = self.hints[key]
            if hint and not self.bad_hints[hint] then target = self:routeHint(hint) end
            self:note("routed", key, target)
            logger.info("Kindle Drawer: menu item", key, "placed by rule in", target)
        end
        routed[target] = routed[target] or {}
        table.insert(routed[target], self:present(key, node or item))
    end
end

function B:route(pages)
    local keys = {}
    for key in pairs(self.items) do keys[#keys + 1] = key end
    table.sort(keys)
    for _, page in pairs(pages) do self:claim(page, 1) end
    local known, routed = L.knownIds(), {}
    for _, key in ipairs(keys) do
        if not self.placed[key] then self:routeKey(key, known, routed) end
    end
    return routed
end

-- Expand slots (Other plugins, the drawer fallback), append items routed to the
-- page and drop captions with nothing under them.
local function finish(page, routed)
    local out = copyKeys(page, {})
    for _, item in ipairs(page) do
        if item.kd_slot then
            for _, r in ipairs(routed[item.kd_slot] or {}) do out[#out + 1] = r end
        else
            out[#out + 1] = item
        end
    end
    if L.ROUTED_PAGES[page.kd_key] then
        for _, r in ipairs(routed[page.kd_key] or {}) do out[#out + 1] = r end
    end
    return Items.dropEmptyCaptions(out)
end

--[[ ctx: tree (menu.tab_item_table), snapshot (L.snapshotFor(tree) or nil),
reader (a book is open), kind ("rolling"/"paging"), drawer (the bottom drawer
shows the moved items), show_networks (function or nil), report (fill
result.report and result.placements; tests and tests/coverage.py). ]]
function L.build(ctx)
    local snap = ctx.snapshot
    local b = setmetatable({ ctx = ctx, tree = ctx.tree or {}, tabs = {}, placed = {}, row_section = {}, claimed = {} }, B)
    if ctx.report then
        b.counts = {}
        b.report = { net = {}, routed = {}, inside = {}, dissolved = {}, disabled = {} }
    end
    b:indexTree()
    if snap then
        b.items, b.hints, b.disabled, b.bad_hints = snap.items, snap.hints, snap.disabled, snap.bad_hints
    else
        b.items, b.hints, b.disabled, b.bad_hints = {}, {}, {}, {}
        for key, node in pairs(b.index) do b.items[key], b.hints[key] = node, node.sorting_hint end
    end
    local ok, MenuSorter = pcall(require, "ui/menusorter")
    b.prefix = ok and type(MenuSorter) == "table" and MenuSorter.orphaned_prefix or nil
    local kind = ctx.kind == "paging" and "paging" or "rolling"
    local lists = {}
    for _, section in ipairs(L.SECTIONS) do lists[#lists + 1] = section end
    if ctx.reader then
        lists[#lists + 1] = L.BOOK
        lists[#lists + 1] = drawerSpecs(kind)
    end
    b:prepare(lists)

    local result = { sections = {}, report = b.report, placements = b.counts }
    local pages, routed_extra = {}, {}
    for _, spec in ipairs(L.SECTIONS) do pages[spec.key] = b:section(spec, spec.key) end
    if ctx.reader then
        pages.book = b:section(L.BOOK, "book")
        local tabs = b:drawerTabs(kind)
        result.drawer_tabs = tabs
        local rows, fallback = {}, {}
        for _, tab in ipairs(tabs) do
            fallback[#fallback + 1] = { kd_caption = tab.title }
            for _, seg in ipairs(tab) do
                if seg.item then rows[#rows + 1] = seg.item; fallback[#fallback + 1] = seg.item end
            end
        end
        pages.drawer = rows
        -- Without the drawer its rows join Reading, one caption per tab.
        if not ctx.drawer then routed_extra.drawer = fallback end
    end
    local routed = b:route(pages)
    for slot, list in pairs(routed_extra) do routed[slot] = list end
    for _, spec in ipairs(L.SECTIONS) do
        local page = finish(pages[spec.key], routed)
        if #page > 0 then result.sections[#result.sections + 1] = page end
    end
    if pages.book then
        local book = finish(pages.book, routed)
        if #book > 0 then result.book = book end
    end
    b.index, b.in_tree, b.parent, b.claimed, b.explicit, b.found = nil, nil, nil, nil, nil, nil
    return result
end

return L
