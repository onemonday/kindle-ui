local WidgetContainer = require("ui/widget/container/widgetcontainer")
local UIManager = require("ui/uimanager")
local Device = require("device")
local Event = require("ui/event")
local Dispatcher = require("dispatcher")
local NetworkMgr = require("ui/network/manager")
local InfoMessage = require("ui/widget/infomessage")
local Drawer = require("drawer")

local Plugin = WidgetContainer:extend{ name = "kindle_drawer", is_doc_only = false }
local choices = {
    { id = "wifi", text = "Wi-Fi" },
    { id = "night", text = "Тёмный режим" },
    { id = "sync", text = "Синхронизация" },
    { id = "light", text = "Подсветка" },
}

function Plugin:init()
    self.settings = G_reader_settings:readSetting("kindle_drawer", {})
    self.settings.hidden = self.settings.hidden or {}
    self.ui.menu:registerToMainMenu(self)
    self:onDispatcherRegisterActions()
    -- Patch only this UI instance; keep the original entry points for teardown.
    self.hooks = {}
    local menu = self.ui.menu
    for _, name in ipairs({ "onTapShowMenu", "onSwipeShowMenu" }) do
        local original = menu[name]
        if original then
            local hook = function(target, ges)
                if self.settings.enabled == false then return original(target, ges) end
                if name == "onTapShowMenu" and target.activation_menu ~= "swipe" then
                    return self:onKindleDrawer()
                elseif name == "onSwipeShowMenu" and target.activation_menu ~= "tap"
                        and ges.direction == "south" then
                    self:onKindleDrawer()
                    self.ui:handleEvent(Event:new("HandledAsSwipe"))
                    return true
                end
                return original(target, ges)
            end
            self.hooks[name] = { original = original, hook = hook }
            menu[name] = hook
        end
    end
end

function Plugin:onDispatcherRegisterActions()
    Dispatcher:registerAction("kindle_drawer", {
        category = "none", event = "KindleDrawer", title = "Шторка Kindle", general = true,
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
            text = choice.text,
            checked_func = function() return not self.settings.hidden[id] end,
            callback = function()
                self.settings.hidden[id] = not self.settings.hidden[id]
                self:save()
            end,
        }
    end
    items.kindle_drawer = {
        text = "Шторка Kindle", sorting_hint = "more_tools", sub_item_table = {
            { text = "Открыть шторку", callback = function() self:onKindleDrawer() end },
            { text = "Открывать вместо верхнего меню",
              checked_func = function() return self.settings.enabled ~= false end,
              callback = function() self.settings.enabled = self.settings.enabled == false; self:save() end },
            { text = "Кнопки шторки", sub_item_table = buttons },
        },
    }
end

function Plugin:available(id)
    if id == "wifi" then return Device:hasWifiToggle() end
    if id == "light" then return Device:hasFrontlight() end
    if id == "sync" then return self.ui.document ~= nil and self.ui.kosync ~= nil end
    return true
end

function Plugin:buttons()
    local result = {}
    for _, choice in ipairs(choices) do
        if not self.settings.hidden[choice.id] and self:available(choice.id) then
            result[#result + 1] = choice
        end
    end
    -- Always reachable, even when all optional buttons are hidden.
    result[#result + 1] = { id = "settings", text = "Все настройки" }
    return result
end

function Plugin:onKindleDrawer()
    if not self.drawer then
        self.drawer = Drawer:new{ owner = self, buttons = self:buttons() }
        UIManager:show(self.drawer)
    end
    return true
end

function Plugin:closeDrawer()
    if self.drawer then UIManager:close(self.drawer) end
end

function Plugin:activate(id)
    if id == "settings" then
        self:closeDrawer()
        self.ui.menu:onShowMenu() -- Original KOReader menu, without recursive interception.
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
    elseif id == "sync" then
        self:closeDrawer()
        if self.ui.kosync and self.ui.document then
            self.ui:handleEvent(Event:new("KOSyncPushProgress"))
        else
            UIManager:show(InfoMessage:new{ text = "Откройте книгу и включите плагин KOSync." })
        end
    end
end

function Plugin:onSuspend() self:closeDrawer() end
function Plugin:onSetDimensions() self:closeDrawer() end
function Plugin:onCloseWidget()
    self:closeDrawer()
    for name, entry in pairs(self.hooks or {}) do
        if self.ui.menu[name] == entry.hook then self.ui.menu[name] = entry.original end
    end
end
return Plugin
