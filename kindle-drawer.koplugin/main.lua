local WidgetContainer = require("ui/widget/container/widgetcontainer")
local UIManager = require("ui/uimanager")
local Device = require("device")
local Event = require("ui/event")
local Dispatcher = require("dispatcher")
local NetworkMgr = require("ui/network/manager")
local InfoMessage = require("ui/widget/infomessage")
local Drawer = require("drawer")
local Layout = require("layout")
local Items = require("menuitems")
local tr = require("l10n").tr

local Plugin = WidgetContainer:extend{ name = "kindle_drawer", is_doc_only = false }
local choices = {
    { id = "wifi", text = "Wi-Fi" },
    { id = "night", text = "Dark Mode" },
    { id = "sync", text = "Sync" },
    { id = "light", text = "Frontlight" },
    { id = "power", text = "Power" },
    { id = "ssh", text = "SSH server", default_hidden = true },
}

function Plugin:init()
    self.settings = G_reader_settings:readSetting("kindle_drawer", {})
    self.settings.hidden = self.settings.hidden or {}
    self.ui.menu:registerToMainMenu(self)
    self:onDispatcherRegisterActions()
    -- Before KOReader sorts its menu: keep a snapshot of the items and survive unknown sorting hints.
    self.sort_guard = Layout.installSortGuard()
    -- Patch only this UI instance; keep the original entry points for teardown.
    self.hooks = {}
    local menu = self.ui.menu
    for _, name in ipairs({ "onTapShowMenu", "onSwipeShowMenu", "onPressMenu", "onShowMenu", "onRebuildMenu", "onMenuSearch" }) do
        local original = menu[name]
        if original then
            local hook = function(target, ...) return self:menuHook(name, original, target, ...) end
            self.hooks[name] = { original = original, hook = hook }
            menu[name] = hook
        end
    end
    local config = self.ui.config
    if config and config.onShowConfigMenu then
        self.bottom_original = config.onShowConfigMenu
        self.bottom_hook = function(target)
            if self.settings.bottom_enabled == false or not Device:isTouchDevice() then return self.bottom_original(target) end
            return self:onKindleBottomDrawer()
        end
        config.onShowConfigMenu = self.bottom_hook
    end
end

-- Top menu entry points. The Kindle-style menu replaces the stock TouchMenu
-- only on touch devices; callers that need the stock menu_container (do_not_show)
-- keep the original path.
function Plugin:menuHook(name, original, menu, ...)
    if name == "onTapShowMenu" then
        if self:onQuickActionsPanel() then return true end
        if menu.activation_menu ~= "swipe" and self:onKindleSettingsMenu() then return true end
    elseif name == "onSwipeShowMenu" then
        local ges = ...
        if ges.direction == "south" and (self.settings.enabled ~= false and self:onKindleDrawer()
                or menu.activation_menu ~= "tap" and self:onKindleSettingsMenu()) then
            self.ui:handleEvent(Event:new("HandledAsSwipe"))
            return true
        end
    elseif name == "onPressMenu" then
        if self:onKindleSettingsMenu() then return true end
    elseif name == "onShowMenu" then
        local tab_index, do_not_show = ...
        if do_not_show then
            self:closeSettingsMenu()
        elseif self:onKindleSettingsMenu(tab_index) then
            return true
        end
    elseif name == "onRebuildMenu" and self.settings_menu then
        -- Rebuild the item tables, then reopen the same page in the new tables.
        local state = self.settings_menu:getState()
        self:closeSettingsMenu()
        local result = original(menu, ...)
        if self:onKindleSettingsMenu() then self.settings_menu:restoreState(state) end
        return result
    elseif name == "onMenuSearch" and self:onKindleSettingsMenu() then
        -- Dispatcher's Menu search: search the new tree, not the classic one.
        self.settings_menu:onShowMenuSearch()
        return true
    end
    return original(menu, ...)
end

function Plugin:kindleMenuActive()
    return self.settings.kindle_menu ~= false and Device:isTouchDevice()
end

function Plugin:onDispatcherRegisterActions()
    Dispatcher:registerAction("kindle_drawer", {
        category = "none", event = "KindleDrawer", title = tr("Kindle Drawer"), general = true,
    })
end

function Plugin:save()
    G_reader_settings:saveSetting("kindle_drawer", self.settings)
end

function Plugin:addToMainMenu(items)
    local buttons = {}
    for _, choice in ipairs(choices) do
        local id = choice.id
        buttons[#buttons + 1] = {
            text = tr(choice.text),
            checked_func = function() return self:isVisible(choice) end,
            callback = function()
                self.settings.hidden[id] = self:isVisible(choice)
                self:save()
            end,
        }
    end
    items.kindle_drawer = {
        text = tr("Kindle Drawer"), sorting_hint = "more_tools", sub_item_table = {
            { text = tr("Kindle-style menu"), hint = "Replaces the KOReader top menu", separator = true,
              checked_func = function() return self.settings.kindle_menu ~= false end,
              callback = function() self.settings.kindle_menu = self.settings.kindle_menu == false; self:save() end },
            { text = tr("Enable top drawer"),
              checked_func = function() return self.settings.enabled ~= false end,
              callback = function() self:closeDrawer(); self.settings.enabled = self.settings.enabled == false; self:save() end },
            { text = tr("Top drawer settings"), sub_item_table = {
                { text = tr("Open drawer"), callback = function() self:onKindleDrawer() end },
                { text = tr("Drawer buttons"), sub_item_table = buttons },
                { text = tr("Header title"), callback = function() self:editTitle() end },
                { text = tr("Dim background"),
                  checked_func = function() return self.settings.dim_background ~= false end,
                  callback = function()
                      self.settings.dim_background = self.settings.dim_background == false
                      self:save()
                  end },
            } },
            { text = tr("Enable bottom drawer"),
              checked_func = function() return self.settings.bottom_enabled ~= false end,
              callback = function() self:closeBottomDrawer(); self.settings.bottom_enabled = self.settings.bottom_enabled == false; self:save() end },
            { text = tr("Bottom drawer settings"), sub_item_table = {
                { text = tr("Open drawer"), enabled_func = function() return self.ui.config ~= nil end,
                  callback = function() self:onKindleBottomDrawer() end },
                { text = tr("Remember last tab"),
                  checked_func = function() return self.settings.bottom_remember_tab ~= false end,
                  callback = function() self.settings.bottom_remember_tab = self.settings.bottom_remember_tab == false; self:save() end },
            } },
            { text = tr("Quick actions panel"),
              checked_func = function() return self.settings.quick_actions_enabled ~= false end,
              callback = function()
                  self:closeQuickActionsPanel()
                  self.settings.quick_actions_enabled = self.settings.quick_actions_enabled == false
                  self:save()
              end },
            { text = tr("Full refresh on open and close"), hint = "Clears e-ink ghosting, a bit slower",
              checked_func = function() return self.settings.full_refresh == true end,
              callback = function()
                  self.settings.full_refresh = not self.settings.full_refresh
                  self:save()
              end },
        },
    }
end

function Plugin:isVisible(choice)
    local hidden = self.settings.hidden[choice.id]
    if hidden == nil then hidden = choice.default_hidden end
    return not hidden
end

function Plugin:editTitle()
    local InputDialog = require("ui/widget/inputdialog")
    local dialog
    dialog = InputDialog:new{
        title = tr("Header title"), input = self.settings.title or "Kindle",
        buttons = {{
            { text = tr("Cancel"), callback = function() UIManager:close(dialog) end },
            { text = tr("Save"), is_enter_default = true, callback = function()
                self.settings.title = dialog:getInputText():gsub("[\r\n]", " ")
                self:save()
                UIManager:close(dialog)
            end },
        }},
    }
    UIManager:show(dialog)
    dialog:onShowKeyboard()
end

function Plugin:showPower()
    self:closeDrawer()
    local ButtonDialog = require("ui/widget/buttondialog")
    local dialog
    local function action(event)
        UIManager:close(dialog)
        self.ui:handleEvent(Event:new(event))
    end
    dialog = ButtonDialog:new{ title = tr("Power"), buttons = {
        {{ text = tr("Restart"), enabled = Device:canRestart(), callback = function() action("Restart") end }},
        {{ text = tr("Sleep"), enabled = Device:canSuspend(), callback = function() action("RequestSuspend") end }},
        {{ text = tr("Exit KOReader"), callback = function() action("Exit") end }},
    }}
    UIManager:show(dialog)
end

function Plugin:available(id)
    if id == "wifi" then return Device:hasWifiToggle() end
    if id == "light" then return Device:hasFrontlight() end
    if id == "ssh" then return self.ui.SSH ~= nil end
    if id == "sync" then return self.ui.document ~= nil and self.ui.kosync ~= nil end
    return true
end

function Plugin:buttons()
    local result = {}
    for _, choice in ipairs(choices) do
        if self:isVisible(choice) and self:available(choice.id) then
            result[#result + 1] = { id = choice.id, text = tr(choice.text) }
        end
    end
    -- Always reachable, even when all optional buttons are hidden.
    result[#result + 1] = { id = "settings", text = tr("All Settings") }
    return result
end

-- Close every panel except keep ("drawer", "bottom_drawer", "quick_actions_panel" or "settings_menu").
function Plugin:closePanels(keep)
    if keep ~= "drawer" then self:closeDrawer() end
    if keep ~= "bottom_drawer" then self:closeBottomDrawer() end
    if keep ~= "quick_actions_panel" then self:closeQuickActionsPanel() end
    if keep ~= "settings_menu" then self:closeSettingsMenu() end
end

function Plugin:onKindleDrawer()
    self:closePanels("drawer")
    if not self.drawer then
        self.drawer = Drawer:new{ owner = self, buttons = self:buttons() }
        UIManager:show(self.drawer, self.drawer.full_refresh and "full" or "ui", Device.screen:getSize())
    end
    return true
end

function Plugin:onKindleBottomDrawer(return_callback)
    local config = self.ui.config
    if not config or not self.ui.document then return false end
    if not Device:isTouchDevice() then return self:showOriginalBottom() end
    if self.bottom_drawer then return true end
    self:closePanels("bottom_drawer")
    if config.config_dialog then config:onCloseConfigMenu() end
    local BottomDrawer = require("bottomdrawer")
    self.bottom_drawer = BottomDrawer:new{
        return_callback = return_callback, owner = self, reader_config = config, ui = self.ui, document = config.document,
        configurable = config.configurable, config_options = config.options,
        -- bottom_tab is the index saved by earlier versions.
        panel_key = self.settings.bottom_remember_tab ~= false and (self.settings.bottom_tab_key or self.settings.bottom_tab) or nil,
        layout_tabs = self:menuLayout().drawer_tabs,
    }
    config.config_dialog = self.bottom_drawer
    if self.ui.keyselection then self.ui.keyselection:stopHighlightIndicator(true) end
    self.ui:handleEvent(Event:new("DisableHinting"))
    UIManager:show(self.bottom_drawer, self.bottom_drawer.full_refresh and "full" or "ui", Device.screen:getSize())
    self.ui:handleEvent(Event:new("HandledAsSwipe"))
    return true
end

function Plugin:onQuickActionsPanel()
    if not self.ui.document or not Device:isTouchDevice() or self.settings.quick_actions_enabled == false then return false end
    self:closePanels("quick_actions_panel")
    if not self.quick_actions_panel then
        local Panel=require("quickactionspanel")
        self.quick_actions_panel=Panel:new{owner=self,ui=self.ui,document=self.ui.document}
        -- Opening overlays the current page, so a normal UI refresh is enough.
        -- Keep the optional full refresh for closing, where it clears E Ink ghosting.
        UIManager:show(self.quick_actions_panel,"ui",Device.screen:getSize())
    end
    return true
end

function Plugin:closeQuickActionsPanel()
    if self.quick_actions_panel then self.quick_actions_panel:closeDialog() end
end

function Plugin:openQuickActionsLayout()
    self:closeQuickActionsPanel()
    if self.settings.bottom_enabled == false then return self:showOriginalBottom() end
    return self:onKindleBottomDrawer(function() self:onQuickActionsPanel() end)
end

function Plugin:closeBottomDrawer()
    if self.bottom_drawer then self.bottom_drawer:closeDialog() end
end

function Plugin:showOriginalBottom()
    self:closeBottomDrawer()
    if self.bottom_original then return self.bottom_original(self.ui.config) end
end

function Plugin:closeDrawer()
    if self.drawer then UIManager:close(self.drawer) end
end

function Plugin:activate(id)
    if id == "settings" then
        self:closeDrawer()
        self.ui.menu:onShowMenu() -- Kindle-style menu when enabled, else the stock one.
    elseif id == "wifi" then
        self:closeDrawer()
        if NetworkMgr:isWifiOn() then NetworkMgr:toggleWifiOff(nil, true)
        else NetworkMgr:toggleWifiOn(nil, false, true) end
    elseif id == "night" then
        self.ui:handleEvent(Event:new("ToggleNightMode"))
        if self.drawer then self.drawer:refresh() end
    elseif id == "light" then
        Device:getPowerDevice():toggleFrontlight()
        if self.drawer then self.drawer:refresh() end
    elseif id == "power" then
        self:showPower()
    elseif id == "ssh" then
        self:closeDrawer()
        local ssh = self.ui.SSH
        if not ssh then
            UIManager:show(InfoMessage:new{ text = tr("Enable the SSH plugin in KOReader first.") })
        else
            ssh:onToggleSSHServer()
        end
    elseif id == "sync" then
        self:closeDrawer()
        if self.ui.kosync and self.ui.document then
            self.ui:handleEvent(Event:new("KOSyncPushProgress"))
        else
            UIManager:show(InfoMessage:new{ text = tr("Open a book and enable KOSync.") })
        end
    end
end

-- Long press opens the button's own settings; buttons without any act as on tap.
-- Dark Mode ignores it, so a long press never toggles the theme by accident.
local settings_menus = { sync = "progress_sync", ssh = "ssh" }
function Plugin:openSettings(id)
    if id == "wifi" then self:closeDrawer(); self:showNetworks()
    elseif id == "light" then self:closeDrawer(); Device:showLightDialog()
    elseif settings_menus[id] then self:closeDrawer(); self:openMenuItem(settings_menus[id])
    elseif id ~= "night" then self:activate(id) end
end

function Plugin:showNetworks()
    if not NetworkMgr:isWifiOn() then
        -- KOReader's own long-press path: turn Wi-Fi on, then show the network list.
        return NetworkMgr:toggleWifiOn(nil, true, true)
    end
    local info = InfoMessage:new{ text = tr("Scanning for networks…") }
    UIManager:show(info)
    UIManager:forceRePaint()
    local networks, err = NetworkMgr:getNetworkList()
    -- Like KOReader: the first scan after a state change may come back empty.
    if networks and #networks == 0 then networks, err = NetworkMgr:getNetworkList() end
    UIManager:close(info)
    if not networks then
        UIManager:show(InfoMessage:new{ text = err or tr("This device cannot list Wi-Fi networks.") })
        return
    end
    table.sort(networks, function(a, b) return a.signal_quality > b.signal_quality end)
    UIManager:show(require("ui/widget/networksetting"):new{ network_list = networks })
end

-- Open the main menu already inside a plugin's submenu, so Back walks up the usual tree.
function Plugin:openMenuItem(key)
    if self:onKindleSettingsMenu() then
        self.settings_menu:openItem(key)
        return
    end
    local menu = self.ui.menu
    if not menu.tab_item_table then menu:setUpdateItemTable() end
    -- MenuSorter tags each placed item with its key as `id`.
    local tab, chain
    for i, items in ipairs(menu.tab_item_table) do
        chain = Items.findChain(items, function(item) return item.id == key end)
        if chain then tab = i; break end
    end
    if tab then
        menu:onShowMenu(tab, true)
        local touch_menu = menu.menu_container[1]
        for _, item in ipairs(chain) do touch_menu:onMenuSelect(item) end
        UIManager:show(menu.menu_container)
        return
    end
    menu:onShowMenu()
end

-- "rolling" or "paging": which ReaderConfig options and drawer tabs apply.
function Plugin:docKind()
    local config = self.ui.config
    local options = config and config.options
    if (options and options.prefix == "kopt") or (not options and self.ui.paging) then return "paging" end
    return "rolling"
end

function Plugin:bottomDrawerActive()
    return self.settings.bottom_enabled ~= false and self.ui.config ~= nil and Device:isTouchDevice()
end

-- The new arrangement of the current KOReader menu tree (layout.lua). Cached per
-- tree: setUpdateItemTable builds a new tree, so a rebuilt menu gets a new layout.
function Plugin:menuLayout()
    local menu = self.ui.menu
    if not menu.tab_item_table then menu:setUpdateItemTable() end
    local tree = menu.tab_item_table
    if tree and not Layout.snapshotFor(tree) and self.sort_guard and not self.resorted then
        -- Sorted before the guard was in place: sort again to see every item.
        self.resorted = true
        menu:setUpdateItemTable()
        tree = menu.tab_item_table
    end
    local reader, kind, drawer = self.ui.document ~= nil, self:docKind(), self:bottomDrawerActive()
    local cache = self.layout_cache
    if cache and cache.tree == tree and cache.reader == reader and cache.kind == kind and cache.drawer == drawer then
        return cache.layout
    end
    local can_list = Device:hasWifiToggle() and not (Device.isAndroid and Device:isAndroid())
    local layout = Layout.build{
        tree = tree, snapshot = Layout.snapshotFor(tree), reader = reader, kind = kind, drawer = drawer,
        show_networks = can_list and function() self:showNetworks() end or nil,
    }
    self.layout_cache = { tree = tree, reader = reader, kind = kind, drawer = drawer, layout = layout }
    return layout
end

-- Drawer rows for menu search: one page per drawer tab.
function Plugin:drawerSearchPages()
    if not self.ui.document or not self:bottomDrawerActive() then return {} end
    local pages = {}
    for _, tab in ipairs(self:menuLayout().drawer_tabs or {}) do
        local items = {}
        for _, seg in ipairs(tab) do if seg.item then items[#items + 1] = seg.item end end
        if #items > 0 then
            pages[#pages + 1] = { drawer_tab = tab.key, title = tr("Bottom drawer") .. " › " .. tab.title, items = items }
        end
    end
    return pages
end

-- A search result in the drawer: open the drawer on its tab and walk the chain inline.
function Plugin:openDrawerChain(tab_key, chain)
    self:closeSettingsMenu()
    if self:onKindleBottomDrawer() and self.bottom_drawer then self.bottom_drawer:openMenuChain(tab_key, chain) end
end

-- Kindle-style top menu: root page, a section with Back to the root, or book actions.
-- tab_index is KOReader's; force opens it even when the stock menu is chosen (Quick actions ⋮).
function Plugin:onKindleSettingsMenu(tab_index, force)
    if not (self:kindleMenuActive() or (force and Device:isTouchDevice())) then return false end
    self:closePanels("settings_menu")
    local menu = self.ui.menu
    if not menu.tab_item_table then menu:setUpdateItemTable() end
    local tab = tab_index and menu.tab_item_table and menu.tab_item_table[tab_index]
    -- Like TouchMenu, never auto-run an action tab such as the file browser.
    local section = tab and tab.remember ~= false and Layout.TAB_SECTIONS[tab.id]
    if self.settings_menu then
        if section then self.settings_menu:openTab(section) end
        return true
    end
    if menu.menu_container then self:closeTopMenu() end -- the stock menu is open
    if self.ui.keyselection then self.ui.keyselection:stopHighlightIndicator(true) end
    local SettingsMenu = require("settingsmenu")
    local widget = SettingsMenu:new{ owner = self, ui = self.ui, menu = menu, layout_data = self:menuLayout() }
    widget:closeConfigDialog()
    self.settings_menu = widget
    -- KOReader closes its menu through menu_container (item callbacks, reader teardown).
    menu.menu_container = widget
    if section then widget:openTab(section) end
    UIManager:show(widget, widget.full_refresh and "full" or "flashui")
    return true
end

-- Book actions page; Back closes it. Opens the Kindle-style menu even when the stock one is chosen.
function Plugin:openBookActions()
    if not self.ui.document then return false end
    self:closeQuickActionsPanel()
    if not self:onKindleSettingsMenu(nil, true) then return false end
    self.settings_menu:openTab("book", true)
    return true
end

function Plugin:closeSettingsMenu()
    if self.settings_menu then self.settings_menu:closeMenu() end
end

-- Close whatever menu_container holds (stock TouchMenu or ours) the way KOReader does,
-- so it saves the last tab.
function Plugin:closeTopMenu()
    local menu = self.ui.menu
    if menu.onCloseReaderMenu then menu:onCloseReaderMenu()
    elseif menu.onCloseFileManagerMenu then menu:onCloseFileManagerMenu() end
end

-- The stock TouchMenu, bypassing our onShowMenu hook.
function Plugin:showClassicMenu(tab_index)
    self:closeSettingsMenu()
    local entry = self.hooks.onShowMenu
    local show = entry and entry.original or self.ui.menu.onShowMenu
    return show(self.ui.menu, tab_index)
end

function Plugin:onSuspend() self:closePanels() end
-- ReaderMenu/FileManagerMenu:onSetDimensions close and reopen the settings menu
-- themselves (menu_container, then the hooked onShowMenu).
function Plugin:onSetDimensions() self:closePanels("settings_menu") end
function Plugin:onCloseWidget()
    self:closePanels()
    if self.sort_guard then Layout.uninstallSortGuard(); self.sort_guard = nil end
    if self.ui.config and self.ui.config.onShowConfigMenu == self.bottom_hook then
        self.ui.config.onShowConfigMenu = self.bottom_original
    end
    for name, entry in pairs(self.hooks or {}) do
        if self.ui.menu[name] == entry.hook then self.ui.menu[name] = entry.original end
    end
end
return Plugin
