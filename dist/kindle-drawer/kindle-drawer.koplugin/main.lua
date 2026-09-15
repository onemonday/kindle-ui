local WidgetContainer = require("ui/widget/container/widgetcontainer")
local UIManager = require("ui/uimanager")
local Device = require("device")
local Event = require("ui/event")
local Dispatcher = require("dispatcher")
local NetworkMgr = require("ui/network/manager")
local InfoMessage = require("ui/widget/infomessage")
local Drawer = require("drawer")
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
            { text = tr("Open drawer"), callback = function() self:onKindleDrawer() end },
            { text = tr("Replace top menu"),
              checked_func = function() return self.settings.enabled ~= false end,
              callback = function() self.settings.enabled = self.settings.enabled == false; self:save() end },
            { text = tr("Drawer buttons"), sub_item_table = buttons },
            { text = tr("Header title"), callback = function() self:editTitle() end },
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
    elseif id == "power" then
        self:showPower()
    elseif id == "ssh" then
        self:closeDrawer()
        local ssh = self.ui.SSH
        if not ssh then
            UIManager:show(InfoMessage:new{ text = tr("Enable the SSH plugin in KOReader first.") })
        elseif ssh:isRunning() then
            UIManager:show(InfoMessage:new{ text = tr("SSH server is already running.") })
        else
            ssh:start()
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

function Plugin:onSuspend() self:closeDrawer() end
function Plugin:onSetDimensions() self:closeDrawer() end
function Plugin:onCloseWidget()
    self:closeDrawer()
    for name, entry in pairs(self.hooks or {}) do
        if self.ui.menu[name] == entry.hook then self.ui.menu[name] = entry.original end
    end
end
return Plugin
