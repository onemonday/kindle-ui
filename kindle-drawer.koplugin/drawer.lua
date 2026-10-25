local InputContainer = require("ui/widget/container/inputcontainer")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local TextWidget = require("ui/widget/textwidget")
local ImageWidget = require("ui/widget/imagewidget")
local Font = require("ui/font")
local Blitbuffer = require("ffi/blitbuffer")
local Device = require("device")
local UIManager = require("ui/uimanager")
local NetworkMgr = require("ui/network/manager")
local L10n = require("l10n")
local tr = L10n.tr
local Screen = Device.screen
local black, white = Blitbuffer.COLOR_BLACK, Blitbuffer.COLOR_WHITE
local source = debug.getinfo(1, "S").source:sub(2)
local icon_dir = source:match("(.*/)") .. "icons/"
local Drawer = InputContainer:extend{ modal = true, covers_header = true }

-- Face for a size in design units at the given scale. Layout uses physical
-- pixels and getFace applies DPI scaling itself, so divide it back out.
function Drawer.face(size, scale)
    return Font:getFace("cfont", size * scale / (Screen:scaleBySize(1000) / 1000))
end

-- Battery level as a whole percent 0-100, or nil when the device reports none.
function Drawer.batteryCapacity(power)
    local capacity = tonumber(power:getCapacity())
    if not capacity or capacity ~= capacity then return nil end
    return math.max(0, math.min(100, math.floor(capacity + 0.5)))
end

function Drawer:init()
    self.dimen = Screen:getSize()
    self.power = Device:getPowerDevice()
    self.dim_background = self.owner.settings.dim_background ~= false
    self.full_refresh = self.owner.settings.full_refresh == true
    local rows = math.ceil(#self.buttons / 3)
    local slider_count = (Device:hasFrontlight() and 1 or 0) + (Device:hasNaturalLight() and 1 or 0)
    local design_height = 124 + rows * 134 + slider_count * 150 + 60
    self.scale = math.min(self.dimen.w / 750, self.dimen.h * 0.88 / design_height)
    self.offset = (self.dimen.w - 750 * self.scale) / 2
    self.height = math.floor(design_height * self.scale)
    self.targets, self.sliders, self.images = {}, {}, {}
    for i, button in ipairs(self.buttons) do
        local row = math.floor((i - 1) / 3)
        local count = math.min(3, #self.buttons - row * 3)
        local col = (i - 1) % 3
        self.targets[#self.targets + 1] = {
            -- Keep the three-column spacing and center incomplete rows.
            x = 375 + (col - (count - 1) / 2) * 250, y = 144 + row * 134, button = button,
        }
    end
    local sy = 124 + rows * 134
    if Device:hasFrontlight() then
        self.sliders[#self.sliders + 1] = { id = "brightness", title = tr("Brightness"), y = sy,
            min = self.power.fl_min, max = self.power.fl_max }
        sy = sy + 150
    end
    if Device:hasNaturalLight() then
        self.sliders[#self.sliders + 1] = { id = "warmth", title = tr("Warmth"), y = sy, min = 0, max = 24 }
    end
    self.ges_events = {}
    for _, name in ipairs({ "tap", "hold", "pan", "pan_release", "swipe", "multiswipe" }) do
        self.ges_events["Drawer_" .. name] = {
            GestureRange:new{ ges = name, range = self.dimen },
        }
    end
    self.key_events.Close = { { "Back" } }
end

function Drawer:refresh()
    UIManager:setDirty(self, "ui", Geom:new{ x = 0, y = 0, w = self.dimen.w, h = self.height })
end

function Drawer:text(bb, value, x, y, size, centered, bold, max_width, vertically_centered)
    local widget = TextWidget:new{ text = value, face = Drawer.face(size, self.scale),
        bold = bold, padding = 0, lang = L10n.language(), para_direction_rtl = false,
        max_width = math.floor((max_width or (centered and 235 or 600)) * self.scale) }
    local width = widget:getSize().w
    local height = widget:getSize().h
    widget:paintTo(bb, math.floor(self.offset + x * self.scale - (centered and width / 2 or 0)),
        math.floor(y * self.scale - (vertically_centered and height / 2 or 0)))
    widget:free()
    return width / self.scale, height / self.scale
end

function Drawer:icon(bb, id, x, y, size, active)
    if active then id = id .. "-active" end
    local key = id .. size
    if not self.images[key] then
        self.images[key] = ImageWidget:new{ file = icon_dir .. id .. ".svg", alpha = true, original_in_nightmode = false,
            width = math.floor(size * self.scale), height = math.floor(size * self.scale) }
    end
    self.images[key]:paintTo(bb, math.floor(self.offset + (x - size / 2) * self.scale),
        math.floor((y - size / 2) * self.scale))
end

function Drawer:value(slider)
    if slider.id == "brightness" then return self.power:frontlightIntensity() end
    -- Present Kindle steps while preserving KOReader's public 0–100 API.
    return math.max(0, math.min(24, math.floor(self.power:frontlightWarmth() * 24 / 100 + 0.5)))
end

-- Draw battery as UI primitives, so it follows the screen's night-mode inversion.
function Drawer:paintBattery(bb, align_to_text)
    local capacity = Drawer.batteryCapacity(self.power)
    self:text(bb, capacity and (capacity .. "%") or "—", 660, 20, 22, true, false, 80)
    local icon_y_offset = 0
    if align_to_text then
        local measure = TextWidget:new{ text = "100%", face = Drawer.face(22, self.scale), padding = 0 }
        icon_y_offset = 20 + measure:getSize().h / self.scale / 2 - 33
        measure:free()
    end
    local function rect(x, y, w, h, color)
        y = y + icon_y_offset
        bb:paintRect(math.floor(self.offset + x * self.scale), math.floor(y * self.scale),
            math.max(1, math.floor(w * self.scale)), math.max(1, math.floor(h * self.scale)), color)
    end
    rect(697, 25, 29, 16, black)
    rect(699, 27, 25, 12, white)
    rect(726, 30, 3, 6, black)
    if self.power:isCharging() then
        self:icon(bb, "charging", 711.5, 33 + icon_y_offset, 20)
    elseif capacity and capacity > 0 then
        rect(701, 29, 21 * capacity / 100, 8, black)
    end
end

function Drawer:paintBackground(bb)
    if not self.dim_background or self.height >= self.dimen.h then return end
    local cell = 3 -- physical pixels, independent of UI DPI scaling
    local period = cell * 2
    local night = Screen.night_mode == true
    if not self.shade_rows or self.shade_night ~= night then
        if self.shade_rows then self.shade_rows:free() end
        self.shade_rows = Blitbuffer.new(self.dimen.w, period, Blitbuffer.TYPE_BB8A)
        -- Blitbuffer.new zero-initializes alpha. Do not use fill(): it makes alpha opaque.
        -- Keep the stipple physically black after whole-screen night inversion.
        local ink = night and white or black
        for x = 0, self.dimen.w - 1, cell do
            local y = (math.floor(x / cell) % 2) * cell
            self.shade_rows:paintRect(x, y, math.min(cell, self.dimen.w - x), cell, ink)
        end
        self.shade_night = night
    end
    for y = self.height, self.dimen.h - 1, period do
        bb:alphablitFrom(self.shade_rows, 0, y, 0, 0, self.dimen.w,
            math.min(period, self.dimen.h - y))
    end
end

function Drawer:paintTo(bb)
    self:paintBackground(bb)
    bb:paintRect(0, 0, self.dimen.w, self.height, white)
    self:text(bb, self.owner.settings.title or "Kindle", 22, 22, 23, false, true, 550)
    self:text(bb, os.date("%H:%M · %d.%m.%Y"), 22, 52, 21)
    self:paintBattery(bb)
    for _, target in ipairs(self.targets) do
        local id = target.button.id
        local state
        if id == "wifi" then state = NetworkMgr:isWifiOn()
        elseif id == "night" then state = G_reader_settings:isTrue("night_mode")
        elseif id == "light" then state = self.power:isFrontlightOn()
        elseif id == "ssh" then state = self.owner.ui.SSH and self.owner.ui.SSH:isRunning() end
        self:icon(bb, id, target.x, target.y, 62, state)
        self:text(bb, target.button.text, target.x, target.y + 44, 21, true)
    end
    if #self.sliders > 0 then
        bb:paintRect(0, math.floor((self.sliders[1].y - 8) * self.scale), self.dimen.w,
            math.max(1, math.floor(self.scale)), Blitbuffer.COLOR_LIGHT_GRAY)
    end
    for _, slider in ipairs(self.sliders) do
        local value = self:value(slider)
        local fraction = math.max(0, math.min(1, (value - slider.min) / (slider.max - slider.min)))
        local knob_x = 90 + fraction * 570
        self:text(bb, slider.title, 40, slider.y + 12, 22)
        self:text(bb, tostring(math.floor(value + 0.5)), knob_x, slider.y + 55, 17, true)
        self:text(bb, "−", 50, slider.y + 82, 30, true)
        self:text(bb, "+", 700, slider.y + 82, 30, true)
        bb:paintRect(math.floor(self.offset + 90 * self.scale), math.floor((slider.y + 103) * self.scale),
            math.floor(570 * self.scale), math.max(1, math.floor(2 * self.scale)), black)
        bb:paintRect(math.floor(self.offset + 90 * self.scale), math.floor((slider.y + 100) * self.scale),
            math.floor(570 * self.scale * fraction), math.max(1, math.floor(7 * self.scale)), black)
        self:icon(bb, "knob", knob_x, slider.y + 104, 42)
    end
    self:icon(bb, "close", 375, self.height / self.scale - 32, 128)
    bb:paintRect(0, self.height - 3, self.dimen.w, 3, black)
end

function Drawer:adjust(slider, x)
    local value
    if x < 80 then value = self:value(slider) - 1
    elseif x > 675 then value = self:value(slider) + 1
    else value = slider.min + (x - 90) / 570 * (slider.max - slider.min) end
    value = math.max(slider.min, math.min(slider.max, math.floor(value + 0.5)))
    if slider.id == "brightness" then self.power:setIntensity(value)
    else self.power:setWarmth(math.floor(value * 100 / 24 + 0.5)) end
    self:refresh()
end

function Drawer:buttonAt(pos)
    local x, y = (pos.x - self.offset) / self.scale, pos.y / self.scale
    for _, target in ipairs(self.targets) do
        if math.abs(x - target.x) < 105 and y >= target.y - 40 and y <= target.y + 95 then
            return target.button
        end
    end
end

function Drawer:onDrawer_tap(_, ges)
    local x, y = (ges.pos.x - self.offset) / self.scale, ges.pos.y / self.scale
    if ges.pos.y >= self.height - 55 * self.scale then return self:onClose() end
    local button = self:buttonAt(ges.pos)
    if button then
        self.owner:activate(button.id)
        return true
    end
    for _, slider in ipairs(self.sliders) do
        if y >= slider.y + 65 and y <= slider.y + 125 then self:adjust(slider, x); return true end
    end
    return true
end

function Drawer:onDrawer_hold(_, ges)
    local button = self:buttonAt(ges.pos)
    if button then self.owner:openSettings(button.id) end
    return true
end

function Drawer:sliderAt(pos)
    if not pos then return nil end
    local x, y = (pos.x - self.offset) / self.scale, pos.y / self.scale
    for _, slider in ipairs(self.sliders) do
        if y >= slider.y + 65 and y <= slider.y + 125 and x >= 80 and x <= 675 then
            return slider
        end
    end
end

function Drawer:onDrawer_pan(_, ges)
    if self.drag_slider == nil then
        self.drag_slider = self:sliderAt(ges.start_pos) or false
    end
    if self.drag_slider then
        local x = (ges.pos.x - self.offset) / self.scale
        self:adjust(self.drag_slider, math.max(90, math.min(660, x)))
    end
    return true
end
function Drawer:onDrawer_pan_release(_, ges)
    if self.drag_slider then
        local x = (ges.pos.x - self.offset) / self.scale
        self:adjust(self.drag_slider, math.max(90, math.min(660, x)))
    end
    self.drag_slider = nil
    return true
end
function Drawer:onDrawer_swipe(_, ges)
    -- Fast drags may end as swipes rather than pan_release.
    local slider = self.drag_slider or self:sliderAt(ges.pos)
    if slider and (ges.direction == "east" or ges.direction == "west") then
        local pos = ges.end_pos
        if pos then
            self:adjust(slider, math.max(90, math.min(660, (pos.x - self.offset) / self.scale)))
        end
    elseif ges.direction == "north" and not slider then
        self:onClose()
    end
    self.drag_slider = nil
    return true
end
function Drawer:onCharging()
    self:refresh()
end
Drawer.onNotCharging = Drawer.onCharging

function Drawer:onDrawer_multiswipe()
    self.drag_slider = nil
    return true
end
function Drawer:onClose() UIManager:close(self); return true end
function Drawer:onCloseWidget()
    if self.owner.drawer == self then self.owner.drawer = nil end
    for _, widget in pairs(self.images) do widget:free() end
    if self.shade_rows then self.shade_rows:free(); self.shade_rows = nil end
    UIManager:setDirty(nil, self.full_refresh and "full" or "partial", Screen:getSize())
end
return Drawer
