-- Keep KOReader's option definitions and application/default/picker handlers intact.
local ConfigDialog = require("ui/widget/configdialog")
local Drawer = require("drawer")
local Device = require("device")
local UIManager = require("ui/uimanager")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local Blitbuffer = require("ffi/blitbuffer")
local IconWidget = require("ui/widget/iconwidget")
local Items = require("menuitems")
local tr = require("l10n").tr
local Screen = Device.screen
local black, white = Blitbuffer.COLOR_BLACK, Blitbuffer.COLOR_WHITE
-- Like the stock ConfigDialog, this is a regular window. A modal drawer would
-- be stacked above KOReader's ordinary SpinWidget/ConfirmBox and swallow input.
local Bottom = ConfigDialog:extend{ modal = false, covers_footer = true }

local priority = { font_size = 1, font_base_weight = 2, font_gamma = 3, contrast = 3, font_fine_tune = 4 }
local function equal(a, b)
    if type(a) ~= "table" or type(b) ~= "table" then return a == b end
    if #a ~= #b then return false end
    for i, v in ipairs(a) do if not equal(v, b[i]) then return false end end
    return true
end
local function display(v)
    if type(v) == "table" then
        local parts = {}; for _, item in ipairs(v) do parts[#parts+1] = tostring(item) end
        return table.concat(parts, " / ")
    end
    return v == nil and "—" or tostring(v)
end

function Bottom:init()
    self.images = self.images or {}
    self.full_refresh = self.owner.settings.full_refresh == true
    self:buildTabs()
    -- panel_key is a tab key; a number is the tab index saved by earlier versions.
    local index = type(self.panel_key) == "number" and self.panel_key or 1
    for i, tab in ipairs(self.tabs) do if tab.key == self.panel_key then index = i end end
    self.panel_index = math.max(1, math.min(#self.tabs, index))
    self.page = 1
    self:update()
    self.ges_events = {}
    for _, name in ipairs({"tap", "hold", "swipe", "pan", "pan_release", "multiswipe"}) do
        self.ges_events["Bottom_" .. name] = {GestureRange:new{ges=name, range=self.dimen}}
    end
    self.key_events.Close = {{"Back"}}
end

-- Tabs from the layout (layout_tabs, for this document kind): its menu rows and
-- captions, plus ReaderConfig options by panel or by name. Every option lands once.
function Bottom:buildTabs()
    local named, listed = {}, {}
    for _, tab in ipairs(self.layout_tabs) do
        for _, seg in ipairs(tab) do
            if seg.opt then named[seg.opt] = true end
            if type(seg.opts) == "table" then for _, icon in ipairs(seg.opts) do listed[icon] = true end end
        end
    end
    local function panelOptions(test, sort)
        local out, order = {}, {}
        for _, panel in ipairs(self.config_options) do
            if test(panel.icon) then
                for _, o in ipairs(panel.options) do
                    if not named[o.name] then out[#out+1] = o; order[o] = #out end
                end
            end
        end
        if sort == "font" then
            table.sort(out, function(a, b)
                return (priority[a.name] or (10 + order[a])) < (priority[b.name] or (10 + order[b]))
            end)
        end
        return out
    end
    self.tabs = {}
    for _, layout_tab in ipairs(self.layout_tabs) do
        local tab = { key = layout_tab.key, title = layout_tab.title }
        for _, seg in ipairs(layout_tab) do
            if seg.caption then
                tab[#tab+1] = { kd_caption = seg.caption, kd_upper = Items.upper(seg.caption) }
            elseif seg.item then
                tab[#tab+1] = { kd_item = seg.item, kd_row = seg.row }
            elseif seg.opt then
                tab[#tab+1] = self:findOptionByName(seg.opt)
            elseif seg.opts == "*" then
                for _, o in ipairs(panelOptions(function(icon) return not listed[icon] end)) do tab[#tab+1] = o end
            elseif seg.opts then
                local set = {}
                for _, icon in ipairs(seg.opts) do set[icon] = true end
                for _, o in ipairs(panelOptions(function(icon) return set[icon] end, seg.sort)) do tab[#tab+1] = o end
            end
        end
        self.tabs[#self.tabs+1] = tab
    end
end

function Bottom:update()
    self.dimen = Screen:getSize()
    self.scale = self.dimen.w / 750
    self.offset = 0
    self.height = math.floor(self.dimen.h * 0.53)
    self.top = self.dimen.h - self.height
    -- Reserve enough room for one slider in landscape without shrinking text.
    local minimum=self.inline_panel and self.inline_panel.kind=="number" and 516 or 246
    if self.height / self.scale < minimum then
        self.height = math.min(self.dimen.h, math.ceil(minimum * self.scale))
        self.top = self.dimen.h - self.height
    end
    self.rows = {}
    if self.inline_panel then
        self.rows=self:inlineRows()
    elseif self.choice_option then
        local o = self.choice_option
        local labels = o.toggle or o.item_text or o.labels or o.values or o.args or {}
        for i,label in ipairs(labels) do
            self.rows[#self.rows+1] = {label=display(label), choice_index=i}
        end
        if o.more_options then self.rows[#self.rows+1] = {label=tr("Set value"), more=true} end
    else
        for _, o in ipairs(self.tabs[self.panel_index]) do
            local show = o.show
            if o.show_func then show = o.show_func(self.configurable, self.document) end
            if o.kd_item and o.kd_item.kd_missing then show = false end
            if show ~= false then self.rows[#self.rows+1] = o end
        end
        Items.dropEmptyCaptions(self.rows)
    end
    -- Pagination and hit testing share the same measured row rectangles.
    self.row_pages = {{}}
    local y, limit = 70, self.height / self.scale - 50
    for _, o in ipairs(self.rows) do
        local height = self.inline_panel and o.height or self.choice_option and 64 or self:optionHeight(o)
        if y + height > limit and #self.row_pages[#self.row_pages] > 0 then
            self.row_pages[#self.row_pages+1] = {}; y = 70
        end
        local page = self.row_pages[#self.row_pages]
        local row = {option=o, y=y, height=height}
        -- Menu rows: display data and columns once per update, read by paint and tap.
        if o.kd_item then row.desc, row.cols = self:menuRow(o.kd_item) end
        page[#page+1] = row
        y = y + height
    end
    self.pages = #self.row_pages
    self.page = math.max(1, math.min(self.page or 1, self.pages))
    self.page_rows = self.row_pages[self.page]
    self.dialog_frame = {dimen=Geom:new{x=0,y=self.top,w=self.dimen.w,h=self.height}}
end

function Bottom:refresh() UIManager:setDirty(self, "ui", self.dialog_frame.dimen) end
function Bottom:text(bb, value, x, y, size, centered, bold, width, vertically_centered)
    return Drawer.text(self, bb, tostring(value), x, y + self.top / self.scale,
        size, centered, bold, width, vertically_centered)
end
function Bottom:rect(bb, x, y, w, h, color)
    bb:paintRect(math.floor(x*self.scale), math.floor(self.top+y*self.scale),
        math.max(1,math.floor(w*self.scale)), math.max(1,math.floor(h*self.scale)), color or black)
end
function Bottom:enabled(o)
    if o.kd_item then return Items.enabled(o.kd_item) end
    if o.kd_caption then return true end
    return not o.enabled_func or o.enabled_func(self.configurable, self.document)
end
function Bottom:title(o)
    if o.name=="font_fine_tune" then return tr("Fine adjustment") end
    return (o.name_text_func and o.name_text_func(self.configurable, self.document))
        or o.name_text or o.alt_name_text or o.name
end
function Bottom:current(o)
    if o.name=="font_fine_tune" then return self.configurable.font_size end
    if o.current_func then return o.current_func() end
    return self.configurable[o.name]
end
function Bottom:position(o)
    local value = self:current(o)
    local values = o.values or o.args or {}
    local nearest, distance
    for i, candidate in ipairs(values) do
        if equal(value, candidate) then return i end
        if type(value)=="number" and type(candidate)=="number" then
            local delta=math.abs(value-candidate)
            if not distance or delta<distance then nearest,distance=i,delta end
        end
    end
    return nearest
end
function Bottom:isSwitch(o)
    return o.name ~= nil and o.args and #o.args==2 and type(o.args[1])=="boolean" and type(o.args[2])=="boolean"
end
function Bottom:isSlider(o)
    if o.name == nil then return false end
    return o.buttonprogress or ((o.name == "font_size" or o.name == "font_base_weight") and #(o.values or o.args or {}) > 1)
end
function Bottom:optionHeight(o)
    if o.kd_caption then return 44 end
    if o.kd_item then return 68 end
    if self:isSlider(o) then return 126 end
    if o.item_icons or o.item_icons_func then return 86 end
    return 68
end

function Bottom:choose(o, index)
    if not self:enabled(o) then return end
    self:onConfigChoose(o.values, o.name, o.event, o.args, index, o.hide_on_apply)
end
function Bottom:more(o)
    if not self:enabled(o) then return end
    self:showEditor(o)
end

function Bottom:paintTo(bb)
    if self.skip_paint then return end
    self:rect(bb,0,0,750,self.height/self.scale,white)
    self:rect(bb,0,0,750,1)
    self:rect(bb,0,61,750,1)
    if self.inline_panel or self.choice_option then
        self:text(bb,"‹ " .. tr("Back"),26,20,22,false,false,140)
        self:text(bb,self.inline_panel and self.inline_panel.title or self:title(self.choice_option),190,20,22,false,true,530)
    else
        if self.return_callback then self:text(bb,"‹ "..tr("Back"),650,20,20,false,false,90) end
        local left,slot=self:tabSlots()
        local size=self:tabFontSize(slot)
        for i,tab in ipairs(self.tabs) do
            local center = left+(i-0.5)*slot
            local width = self:text(bb,tab.title,center,31,size,true,i==self.panel_index,slot-8,true)
            if i==self.panel_index then self:rect(bb,center-width/2,57,width,3) end
        end
    end
    for _,row in ipairs(self.page_rows) do
        local o, y = row.option, row.y
        if self.inline_panel then
            self:paintInlineRow(bb,row)
        elseif self.choice_option then
            local values = self.choice_option.values or self.choice_option.args or {}
            local selected = o.choice_index and equal(self:current(self.choice_option),values[o.choice_index])
            self:text(bb,selected and "✓" or (o.more and "›" or "○"),48,y+20,23,true)
            self:text(bb,o.label,90,y+20,21,false,selected,620)
        elseif o.kd_caption then
            self:text(bb,o.kd_upper,30,y+row.height-24,16,false,true,690,true)
        elseif o.kd_item then
            self:paintMenuRow(bb,row,y,row.height)
        else
            local enabled=self:enabled(o)
            self:text(bb,self:title(o),30,y+row.height/2,21,false,true,260,true)
            local position=self:position(o)
            local values=o.values or o.args or {}
            local icons=o.item_icons_func and o.item_icons_func(self.configurable,self.document) or o.item_icons
            if self:isSlider(o) then
                local fraction = position and (position-1)/math.max(1,#values-1) or 0
                local x=350+fraction*290
                self:text(bb,display(self:current(o)),x,y+28,17,true,false,180)
                self:text(bb,"−",310,y+77,30,true,false,nil,true)
                self:text(bb,"+",677,y+77,30,true,false,nil,true)
                self:rect(bb,350,y+77,290,1)
                if fraction>0 then self:rect(bb,350,y+75,290*fraction,5) end
                Drawer.icon(self,bb,"knob",x,y+77+self.top/self.scale,36)
            elseif self:isSwitch(o) then
                Drawer.icon(self,bb,position==2 and "switch-on" or "switch-off",660,y+34+self.top/self.scale,58)
            elseif icons then
                for i,icon in ipairs(icons) do
                    local x=310+(i-1)*370/#icons
                    local key=icon..self.scale
                    if not self.images[key] then
                        self.images[key]=IconWidget:new{icon=icon,width=math.floor(45*self.scale),height=math.floor(45*self.scale)}
                    end
                    self.images[key]:paintTo(bb,math.floor(x*self.scale),math.floor(self.top+(y+22)*self.scale))
                    if i==position then self:rect(bb,x,y+72,45,3) end
                end
            else
                local labels=o.toggle or o.item_text or o.labels
                local label=position and labels and labels[position] or display(self:current(o))
                self:text(bb,label,320,y+22,21,false,false,350)
            end
            if o.more_options or (not self:isSlider(o) and not self:isSwitch(o) and not icons) then
                self:text(bb,"›",715,y+(self:isSlider(o) and 56 or 20),30,true)
            end
            if not enabled then self:text(bb,"—",715,y+row.height-24,18,true) end
        end
        if not o.kd_caption then self:rect(bb,30,y+row.height-1,690,1,Blitbuffer.COLOR_LIGHT_GRAY) end
    end
    if self.inline_panel then self:paintInlineFooter(bb); return end
    local y=self.height/self.scale-38
    self:text(bb,tr(self.choice_option and "Hold: set as default" or "KOReader settings"),30,y,18,false,false,490)
    if self.pages>1 then
        self:text(bb,"‹",560,y-5,27,true)
        self:text(bb,self.page.." / "..self.pages,625,y,17,true)
        self:text(bb,"›",710,y-5,27,true)
    end
end

-- Equal header slots for the tabs, left of "‹ Back" when it is shown.
function Bottom:tabSlots()
    local left, right = 10, self.return_callback and 630 or 740
    return left, (right-left)/#self.tabs
end
-- Largest title size at which every tab title fits its slot, bold as when active.
function Bottom:tabFontSize(slot)
    local key=slot..":"..self.scale
    if self.tab_font and self.tab_font.key==key then return self.tab_font.size end
    local chosen=16
    for _,size in ipairs({22,21,20,19,18,17}) do
        local fits=true
        for _,tab in ipairs(self.tabs) do
            if Drawer.measure(self,tab.title,size,true)>slot-8 then fits=false; break end
        end
        if fits then chosen=size; break end
    end
    self.tab_font={key=key,size=chosen}
    return chosen
end
function Bottom:rowAt(pos)
    local y=(pos.y-self.top)/self.scale
    for _,row in ipairs(self.page_rows) do
        if y>=row.y and y<row.y+row.height then return row.option,row.y,row end
    end
end

function Bottom:selectTab(index)
    self.drag=nil; self.choice_option=nil; self.choice_parent_page=nil
    self.panel_index=index; self.page=1; self:update(); self:refresh()
end
function Bottom:turnPage(delta)
    if self:turnInlinePage(delta) then return end
    self.page=math.max(1,math.min(self.pages,self.page+delta)); self:update(); self:refresh()
end
function Bottom:adjust(o,x)
    if not self:enabled(o) then return end
    local values=o.values or o.args or {}
    if #values==0 then return end
    if x<335 or x>657 then
        if o.buttonprogress and o.fine_tune then
            self:onConfigFineTuneChoose(o.values,o.name,o.event,o.args,x<335 and "-" or "+",o.hide_on_apply,o.fine_tune_param)
        else
            local current=self:current(o)
            if type(current)=="number" and type(values[1])=="number" then
                local next_index, distance
                for i,value in ipairs(values) do
                    local delta=(value-current)*(x<335 and -1 or 1)
                    if delta>0 and (not distance or delta<distance) then next_index,distance=i,delta end
                end
                if next_index then self:choose(o,next_index) end
            else
                self:choose(o,math.max(1,math.min(#values,(self:position(o) or 1)+(x<335 and -1 or 1))))
            end
        end
    else
        self:choose(o,math.max(1,math.min(#values,math.floor((x-350)/290*(#values-1)+1.5))))
    end
end
function Bottom:onBottom_tap(_,ges)
    if self.skip_paint then return true end
    local x,y=ges.pos.x/self.scale,(ges.pos.y-self.top)/self.scale
    if y<0 then return self:closeDialog() end
    if y<62 then
        if self.inline_panel then
            if x<180 then self:backInline() end
            return true
        end
        if self.choice_option then
            if x<180 then self:backFromChoices() end
            return true
        end
        if x>=630 and self.return_callback then return self:onClose() end
        local left,slot=self:tabSlots()
        local index=math.floor((x-left)/slot)+1
        if x>=left and index>=1 and index<=#self.tabs then self:selectTab(index) end
        return true
    end
    if y>=self.height/self.scale-42 then
        if self.inline_panel then return self:inlineFooter(x) end
        if x<520 then
            if not self.choice_option then self.owner:showOriginalBottom() end
        elseif x<595 then self:turnPage(-1) else self:turnPage(1) end
        return true
    end
    local o,row_y,page_row=self:rowAt(ges.pos)
    if self.inline_panel then return self:inlineTap(o,x,y-(row_y or 0)) end
    if self.choice_option then
        if o then
            local option = self.choice_option
            if o.more then self:more(option)
            elseif self:enabled(option) then
                self:backFromChoices()
                self:choose(option,o.choice_index)
            end
        end
        return true
    end
    if o and o.kd_caption then return true end
    if o and o.kd_item then return self:menuRowTap(o.kd_item,page_row.cols,x) end
    if not o or not self:enabled(o) then return true end
    if x>=695 and o.more_options then self:more(o)
    elseif self:isSlider(o) and x>=290 then self:adjust(o,x)
    elseif self:isSwitch(o) then self:choose(o,self:position(o)==2 and 1 or 2)
    else
        local icons=o.item_icons_func and o.item_icons_func(self.configurable,self.document) or o.item_icons
        if icons and x>=300 and x<690 then
            self:choose(o,math.max(1,math.min(#icons,math.floor((x-310)/(370/#icons))+1)))
        elseif not icons and not self:isSlider(o) then self:showChoices(o) end
    end
    return true
end
function Bottom:showChoices(o)
    if not self:enabled(o) then return end
    if not self.choice_option then self.choice_parent_page=self.page end
    self.choice_option=o; self.page=1; self.drag=nil
    self:update(); self:refresh()
end
function Bottom:backFromChoices()
    if not self.choice_option then return false end
    self.choice_option=nil; self.page=self.choice_parent_page or 1
    self.choice_parent_page=nil; self.drag=nil
    self:update(); self:refresh()
    return true
end
function Bottom:onClose()
    if self:backInline() then return true end
    if self:backFromChoices() then return true end
    local callback=self.return_callback
    self:closeDialog()
    if callback then callback() end
    return true
end
function Bottom:onBottom_hold(_,ges)
    if self.skip_paint then return true end
    local o,row_y,page_row=self:rowAt(ges.pos)
    if self.inline_panel then return self:inlineTap(o,ges.pos.x/self.scale,(ges.pos.y-self.top)/self.scale-(row_y or 0),true) end
    if not o or o.kd_caption then return true end
    if o.kd_item then return self:menuRowTap(o.kd_item,page_row.cols,ges.pos.x/self.scale,true) end
    if self.choice_option then
        local option=self.choice_option
        if self:enabled(option) and o.choice_index then
            self:onMakeDefault(option.name,self:title(option),option.values or option.args,
                option.toggle or option.item_text or option.labels or option.values or option.args,o.choice_index)
        end
        return true
    end
    if ges.pos.x/self.scale<290 and o.name_text_hold_callback then
        self:showHelp(o)
    elseif self:enabled(o) then
        local x=ges.pos.x/self.scale
        local values=o.values or o.args
        local labels=o.labels or o.toggle or values
        if self:isSlider(o) and x>=290 and x<695 then
            if (x<335 or x>657) and o.fine_tune then
                self:onMakeFineTuneDefault(o.name,self:title(o),values,labels,x<335 and "-" or "+")
            elseif values and #values>0 then
                local position=math.max(1,math.min(#values,math.floor((x-350)/290*(#values-1)+1.5)))
                self:onMakeDefault(o.name,self:title(o),values,labels,position)
            end
        elseif self:isSwitch(o) then
            self:showChoices(o)
        else
            local icons=o.item_icons_func and o.item_icons_func(self.configurable,self.document) or o.item_icons
            if icons and values and x>=300 and x<690 then
                local position=math.max(1,math.min(#icons,math.floor((x-310)/(370/#icons))+1))
                self:onMakeDefault(o.name,self:title(o),values,labels,position)
            end
        end
    end
    return true
end
function Bottom:onBottom_pan(_,ges)
    if self.inline_panel then
        if self.drag==nil then
            local row,y
            if ges.start_pos then row,y=self:rowAt(ges.start_pos) end
            local x=ges.start_pos and ges.start_pos.x/self.scale or 0
            self.drag=row and row.kind=="field" and x>=335 and x<=657
                and (ges.start_pos.y-self.top)/self.scale-y>=50 and {inline_row=row} or false
        end
        return true
    end
    if self.skip_paint or self.choice_option then self.drag=false; return true end
    if self.drag==nil then
        local o=ges.start_pos and self:rowAt(ges.start_pos)
        local x=ges.start_pos and ges.start_pos.x/self.scale or 0
        self.drag=o and self:isSlider(o) and self:enabled(o) and x>=335 and x<=657 and o or false
    end
    -- Apply once at release: reflowing a book during every pan event is expensive.
    return true
end
function Bottom:onBottom_pan_release(_,ges)
    local o=self.drag; self.drag=nil
    if o and o.inline_row then self:inlineTap(o.inline_row,math.max(350,math.min(640,ges.pos.x/self.scale)),77)
    elseif o then self:adjust(o,math.max(350,math.min(640,ges.pos.x/self.scale))) end
    return true
end
function Bottom:onBottom_swipe(_,ges)
    local o=self.drag
    self.drag=nil
    if o then
        if ges.end_pos then
            local x=math.max(350,math.min(640,ges.end_pos.x/self.scale))
            if o.inline_row then self:inlineTap(o.inline_row,x,77) else self:adjust(o,x) end
        end
        return true
    end
    if ges.direction=="south" then return self:onClose()
    elseif ges.direction=="west" then self:turnPage(1)
    elseif ges.direction=="east" then self:turnPage(-1) end
    return true
end
function Bottom:onBottom_multiswipe() self.drag=nil; return true end
function Bottom:onCloseWidget()
    self.closed=true
    self:freeInline()
    for _,image in pairs(self.images) do image:free() end
    self.images={}
    if self.owner.bottom_drawer==self then self.owner.bottom_drawer=nil end
    if self.reader_config.config_dialog==self then
        self.reader_config.config_dialog=nil
        self.ui:handleEvent(require("ui/event"):new("RestoreHinting"))
    end
    self.owner.settings.bottom_tab=nil
    self.owner.settings.bottom_tab_key=self.tabs[self.panel_index] and self.tabs[self.panel_index].key
    self.owner:save()
    UIManager:setDirty(nil,self.full_refresh and "full" or "partial",Screen:getSize())
end
-- A menu search result: open its tab, then walk the chain into inline pages.
function Bottom:openMenuChain(tab_key, chain)
    for i, tab in ipairs(self.tabs) do
        if tab.key == tab_key then self:selectTab(i) end
    end
    local host = self:menuHost()
    for k, wanted in ipairs(chain) do
        local item
        if k == 1 then
            for page, rows in ipairs(self.row_pages) do
                for _, row in ipairs(rows) do
                    if row.option.kd_item == wanted then item = wanted; self.page = page end
                end
            end
            self:update(); self:refresh()
        else
            item = Items.findIn(host.item_table, wanted)
        end
        if not item or not Items.hasSub(item) or not Items.enabled(item) then return end
        host:onMenuSelect(item)
    end
end
for name,method in pairs(require("inlinepanels")) do Bottom[name]=method end
return Bottom
