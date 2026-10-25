-- In-drawer editors. Values/events come from ReaderConfig, never from Kindle presets.
local UIManager = require("ui/uimanager")
local Device = require("device")
local Font = require("ui/font")
local TextBoxWidget = require("ui/widget/textboxwidget")
local Drawer = require("drawer")
local Items = require("menuitems")
local _ = require("gettext")
local L10n = require("l10n")
local tr = L10n.tr
local M = {}
local function copy(v)
    if type(v)~="table" then return v end
    local out={}; for k,item in pairs(v) do out[k]=copy(item) end; return out
end
local function valueText(v)
    if type(v)=="table" then
        local out={}; for i,item in ipairs(v) do out[i]=valueText(item) end
        return table.concat(out," / ")
    end
    if v==nil then return tr("Not set") end
    if type(v)=="boolean" then return tr(v and "On" or "Off") end
    return tostring(v)
end
function M:pushInline(panel, replace)
    self.drag=nil
    self.inline_stack=self.inline_stack or {}
    if not replace then
        self.inline_stack[#self.inline_stack+1]={panel=self.inline_panel,page=self.page}
    elseif self.inline_panel and self.inline_panel.box then self.inline_panel.box:free() end
    self.inline_panel=panel; self.page=1
    self:update(); UIManager:setDirty("all","ui",self.dimen)
    if self.menu_host then self.menu_host:sync() end
end
function M:backInline()
    if not self.inline_panel then return false end
    if self.inline_panel.box then self.inline_panel.box:free() end
    local previous=table.remove(self.inline_stack)
    self.inline_panel=previous and previous.panel or nil
    self.page=previous and previous.page or 1
    self.drag=nil
    self:update(); UIManager:setDirty("all","ui",self.dimen)
    if self.menu_host then self.menu_host:sync() end
    return true
end
function M:freeInline()
    if self.inline_panel and self.inline_panel.box then self.inline_panel.box:free() end
    for _,entry in ipairs(self.inline_stack or {}) do if entry.panel and entry.panel.box then entry.panel.box:free() end end
    self.inline_panel=nil; self.inline_stack={}
    if self.menu_host then self.menu_host:sync() end
end
function M:showEditor(o, replace)
    if not self:enabled(o) then return end
    local p=o.more_options_param or {}
    local name=p.name or o.name
    local panel={kind="editor",title=p.name_text or self:title(o),option=o,params=p,name=name,event=p.event or o.event,fields={}}
    local function field(label,key,min,max,step,hold,value,default)
        return {label=label,key=key,min=min,max=max,step=step or 1,hold=hold or step or 1,
            value=copy(value),default=copy(default),precision=p.precision,unit=p.unit}
    end
    local function defaultFor(key,fallback)
        local v=G_reader_settings:readSetting(self.config_options.prefix.."_"..key)
        if v==nil then v=fallback end
        return copy(v)
    end
    if p.left_min~=nil then
        local values,defaults
        if p.names then
            values={self.configurable[p.names[1]],self.configurable[p.names[2]]}
            defaults={defaultFor(p.names[1],self:findOptionByName(p.names[1]).default_value),
                defaultFor(p.names[2],self:findOptionByName(p.names[2]).default_value)}
        else
            values=copy(self.configurable[name]); defaults=defaultFor(name,o.default_value)
        end
        panel.fields={
            field(p.left_text or tr("Left"),p.names and p.names[1],p.left_min,p.left_max,p.left_step,p.left_hold_step,values[1],defaults[1]),
            field(p.right_text or tr("Right"),p.names and p.names[2],p.right_min,p.right_max,p.right_step,p.right_hold_step,values[2],defaults[2]),
        }
    else
        local values=o.values or {}
        local f=field(tr("Value"),name,p.value_min or values[1],p.value_max or values[#values],p.value_step,
            p.value_hold_step or (#values>1 and math.abs(values[2]-values[1]) or 1),
            self.configurable[name],defaultFor(name,(self:findOptionByName(name) or o).default_value))
        if p.value_table then
            f.value_table=p.value_table; f.shift=p.value_table_shift or 0
            f.value=f.value+f.shift
            if f.default~=nil then f.default=f.default+f.shift end
            f.min=1; f.max=#f.value_table; f.step=1; f.hold=1
        end
        panel.fields={f}
    end
    self:pushInline(panel,replace)
end
function M:fieldText(f,value)
    if value==nil then value=f.value end
    if f.value_table then value=f.value_table[value] end
    if value==nil then return tr("Not set") end
    local text=f.precision and string.format(f.precision,value) or valueText(value)
    return text..(f.unit and " "..f.unit or "")
end
function M:editorValue(panel)
    local values={}
    for i,f in ipairs(panel.fields) do values[i]=f.value-(f.shift or 0) end
    return #values==1 and values[1] or values
end
function M:applyEditor(panel)
    if self.closed or not self:enabled(panel.option) then return end
    local value=copy(self:editorValue(panel))
    UIManager:tickAfterNext(function()
        if self.closed then return end
        if panel.params.names then
            for i,key in ipairs(panel.params.names) do self:onConfigChoice(key,value[i]) end
        else self:onConfigChoice(panel.name,value) end
        -- Keep the drawer visible while the document reflows. The callback is
        -- the same completion contract used by ConfigDialog's precise picker.
        self:onConfigEvent(panel.event,value,function()
            if not self.closed then self:update(); self:refresh() end
        end)
        if not self.closed then self:update(); self:refresh() end
    end)
end
function M:confirmDefault(title, assignments, description, on_saved)
    self:pushInline{kind="confirm",title=tr("Set as default"),
        message=title.."\n\n"..description,assignments=copy(assignments),on_saved=on_saved}
end
function M:onMakeDefault(name,title,values,labels,index)
    if name=="font_fine_tune" or not values or values[index]==nil then return end
    self:confirmDefault(title,{[name]=values[index]},valueText(labels and labels[index] or values[index]))
end
function M:onMakeFineTuneDefault(name,title,values,labels,direction)
    local value=self.configurable[name]
    if value==nil then value=direction=="-" and values[1] or values[#values] end
    self:confirmDefault(title,{[name]=value},valueText(value))
end
function M:saveEditorDefault(panel)
    local value=self:editorValue(panel)
    local assignments={}
    if panel.params.names then for i,key in ipairs(panel.params.names) do assignments[key]=value[i] end
    else assignments[panel.name]=value end
    local parts={}; for i,f in ipairs(panel.fields) do parts[i]=self:fieldText(f) end
    self:confirmDefault(panel.title,assignments,table.concat(parts," / "),function()
        for _,f in ipairs(panel.fields) do f.default=copy(f.value) end
    end)
end
function M:showInfo(title,text)
    self:pushInline{kind="info",title=title,message=text,text_page=1}
end
function M:describeValue(o,value)
    if value==nil then return tr("Not set") end
    local p=o.more_options_param or {}
    if p.value_table then return valueText(p.value_table[value+(p.value_table_shift or 0)]) end
    if o.show_true_value_func then return valueText(o.show_true_value_func(value)) end
    local labels=o.toggle or o.labels or o.item_text
    if labels and o.values then
        for i,v in ipairs(o.values) do if valueText(v)==valueText(value) then return valueText(labels[i]) end end
    end
    local unit=o.name_text_unit
    if o.name=="h_page_margins" or unit==true then unit=G_reader_settings:readSetting("dimension_units","mm") end
    if unit then
        local format=require("ui/data/optionsutil").formatFlexSize
        if type(value)=="table" then
            local parts={}; for i,v in ipairs(value) do parts[i]=format(v,unit) end
            return table.concat(parts," / ")
        end
        return format(value,unit)
    end
    return valueText(value)
end
function M:showHelp(o)
    if o.name=="font_fine_tune" then
        o={name="font_size",name_text=_("Font Size")}
        if self.config_options.prefix=="copt" then o.name_text_unit="pt"
        else o.help_text=_("In reflow mode, sets a font scaling factor that is applied to the original document font sizes.") end
    end
    local parts={o.help_text or ""}
    if o.help_text_func then parts[#parts+1]=o.help_text_func(self.configurable,self.document) or "" end
    parts[#parts+1]=tr("Current value")..": "..self:describeValue(o,self:current(o))
    parts[#parts+1]=tr("Default value")..": "..self:describeValue(o,G_reader_settings:readSetting(self.config_options.prefix.."_"..o.name))
    self:showInfo(self:title(o),table.concat(parts,"\n\n"))
end
function M:editField(f)
    if f.value_table then
        local rows={}; for i,value in ipairs(f.value_table) do rows[i]={kind="enum",height=64,label=valueText(value),index=i,field=f} end
        self:pushInline{kind="enum",title=f.label,rows=rows}
    else self:pushInline{kind="number",title=f.label,field=f,input=tostring(f.value),replace_input=true} end
end
function M:adjustField(f,direction,hold)
    local value=f.value+direction*(hold and f.hold or f.step)
    f.value=math.max(f.min,math.min(f.max,math.floor(value*1000000+0.5)/1000000))
    self:refresh()
end
function M:inlineRows()
    local panel=self.inline_panel
    if panel.kind=="editor" then
        local rows={}
        for _,f in ipairs(panel.fields) do rows[#rows+1]={kind="field",height=126,field=f} end
        local parts={}; for i,f in ipairs(panel.fields) do parts[i]=f.default~=nil and self:fieldText(f,f.default) or tr("Not set") end
        rows[#rows+1]={kind="restore",height=64,label=tr("Default value")..": "..table.concat(parts," / ")}
        if panel.params.info_text then rows[#rows+1]={kind="info",height=56,label=tr("About this setting")} end
        if panel.params.other_button then rows[#rows+1]={kind="other",height=56,label=panel.params.other_button.text} end
        return rows
    elseif panel.kind=="enum" then return panel.rows
    elseif panel.kind=="menu" then
        local rows={}
        for _,item in ipairs(panel.items or {}) do
            if type(item)=="table" and not item.kd_caption then
                local desc,cols=self:menuRow(item)
                rows[#rows+1]={kind="menuitem",height=64,item=item,desc=desc,cols=cols}
            end
        end
        return rows
    elseif panel.kind=="number" then
        return {{kind="input",height=64},
            {kind="keys",height=64,keys={"7","8","9"}},{kind="keys",height=64,keys={"4","5","6"}},
            {kind="keys",height=64,keys={"1","2","3"}},{kind="keys",height=64,keys={"−","0","."}},
            {kind="keys",height=56,keys={tr("Clear"),"⌫"}}}
    else
        local height=math.floor(self.height-132*self.scale)
        if not panel.box or panel.box_width~=self.dimen.w or panel.box_height~=height then
            if panel.box then panel.box:free() end
            panel.box=TextBoxWidget:new{text=panel.message,width=math.floor(690*self.scale),height=height,
                face=Font:getFace("cfont",21*self.scale/(Device.screen:scaleBySize(1000)/1000)),
                lang=L10n.language(),para_direction_rtl=false}
            panel.box_width=self.dimen.w;panel.box_height=height
        end
        panel.text_pages=math.max(1,math.ceil(panel.box:getAllLineCount()/math.max(1,panel.box:getVisLineCount())))
        panel.text_page=math.min(panel.text_page or 1,panel.text_pages)
        panel.box:scrollToRatio((panel.text_page-1)/math.max(1,panel.text_pages-1),true)
        return {{kind="text",height=height/self.scale}}
    end
end
function M:paintInlineRow(bb,row)
    local item,y=row.option,row.y
    local panel=self.inline_panel
    if item.kind=="field" then
        local f=item.field
        self:text(bb,f.label,30,y+60,21,false,true,245)
        local fraction=math.max(0,math.min(1,(f.value-f.min)/math.max(1e-9,f.max-f.min)))
        local x=350+fraction*290
        self:text(bb,self:fieldText(f),x,y+18,19,true,false,200)
        self:text(bb,"−",310,y+56,30,true); self:text(bb,"+",677,y+56,30,true)
        self:rect(bb,350,y+77,290,1)
        if fraction>0 then self:rect(bb,350,y+75,290*fraction,5) end
        Drawer.icon(self,bb,"knob",x,y+77+self.top/self.scale,36)
    elseif item.kind=="input" then
        self:text(bb,panel.error or panel.input,375,y+12,24,true,false,690)
    elseif item.kind=="keys" then
        for i,key in ipairs(item.keys) do self:text(bb,key,(i-0.5)*750/#item.keys,y+16,25,true,false,220) end
    elseif item.kind=="text" then
        panel.box:paintTo(bb,math.floor(30*self.scale),math.floor(self.top+(y+4)*self.scale))
    elseif item.kind=="menuitem" then
        self:paintMenuRow(bb,item,y,item.height)
    else
        local selected=item.kind=="enum" and item.field.value==item.index
        self:text(bb,selected and "✓" or "›",48,y+19,23,true)
        self:text(bb,item.label,90,y+20,20,false,selected,620)
    end
end
function M:paintInlineFooter(bb)
    local panel=self.inline_panel
    local y=self.height/self.scale-38
    if panel.kind=="editor" then
        self:text(bb,tr("Set as default"),30,y,18,false,false,255)
        self:text(bb,tr("Apply"),365,y,20,true,true,150)
    elseif panel.kind=="number" then self:text(bb,tr("Done"),375,y,21,true,true,200)
    elseif panel.kind=="confirm" then self:text(bb,tr("Save"),210,y,21,true,true,300) end
    local page,pages=self.page,self.pages
    if panel.box then page,pages=panel.text_page,panel.text_pages end
    if pages>1 then
        self:text(bb,"‹",560,y-5,27,true);self:text(bb,page.." / "..pages,625,y,17,true);self:text(bb,"›",710,y-5,27,true)
    end
end
function M:turnInlinePage(delta)
    local panel=self.inline_panel
    if panel and panel.box then
        panel.text_page=math.max(1,math.min(panel.text_pages,panel.text_page+delta))
        panel.box:scrollToRatio((panel.text_page-1)/math.max(1,panel.text_pages-1),true)
        self:refresh();return true
    end
    return false
end
function M:inlineFooter(x)
    local panel=self.inline_panel
    if x>=520 and panel.kind~="number" then self:turnPage(x<595 and -1 or 1)
    elseif panel.kind=="editor" then
        if x<280 then self:saveEditorDefault(panel) elseif x<500 then self:applyEditor(panel) end
    elseif panel.kind=="confirm" then
        for key,value in pairs(panel.assignments) do G_reader_settings:saveSetting(self.config_options.prefix.."_"..key,copy(value)) end
        if panel.on_saved then panel.on_saved() end
        self:backInline()
    elseif panel.kind=="number" then
        local v=tonumber(panel.input)
        local f=panel.field
        if not v or v~=v or v<f.min or v>f.max then
            panel.error=tr("Range")..": "..f.min.." … "..f.max;self:refresh()
        else f.value=v;self:backInline() end
    end
    return true
end
function M:inlineTap(item,x,y,hold)
    local panel=self.inline_panel
    if not item then return true end
    if item.kind=="menuitem" then return self:menuRowTap(item.item,item.cols,x,hold) end
    if item.kind=="field" then
        local f=item.field
        if y<50 and x>=260 then self:editField(f)
        elseif x>=280 and x<335 then self:adjustField(f,-1,hold)
        elseif x>657 and x<710 then self:adjustField(f,1,hold)
        elseif x>=335 and x<=657 then
            local v=f.min+(math.max(350,math.min(640,x))-350)/290*(f.max-f.min)
            f.value=math.max(f.min,math.min(f.max,f.min+math.floor((v-f.min)/f.step+0.5)*f.step)); self:refresh()
        end
    elseif item.kind=="restore" then
        for _,f in ipairs(panel.fields) do if f.default~=nil then f.value=math.max(f.min,math.min(f.max,f.default)) end end
        self:refresh()
    elseif item.kind=="enum" then item.field.value=item.index;self:backInline()
    elseif item.kind=="info" then self:showInfo(panel.title,panel.params.info_text)
    elseif item.kind=="other" then self:showEditor(self:findOptionByName(panel.params.other_button.other_option),true)
    elseif item.kind=="keys" then
        local key=item.keys[math.min(#item.keys,math.floor(x/(750/#item.keys))+1)]
        panel.error=nil
        if key==tr("Clear") then panel.input="";panel.replace_input=false
        elseif key=="⌫" then panel.input=panel.input:sub(1,-2);panel.replace_input=false
        elseif key=="−" then
            if panel.input:sub(1,1)=="-" then panel.input=panel.input:sub(2) else panel.input="-"..panel.input end
            panel.replace_input=false
        else
            if panel.replace_input then panel.input="";panel.replace_input=false end
            if #panel.input<16 and (key~="." or not panel.input:find(".",1,true)) then panel.input=panel.input..key end
        end
        self:refresh()
    end
    return true
end
-- KOReader menu items inside the drawer. The host offers TouchMenu's surface to
-- item callbacks (touchmenu_instance) and keeps item_table in step with the
-- inline pages; selection rules are shared with the top menu (menuitems.lua).
local Host={}
Host.__index=Host
function Host:closeConfigDialog() end
function Host:pushPage(item,sub_item_table)
    local d=self.drawer
    d:pushInline{kind="menu",title=Items.describe(item).label,items=sub_item_table}
end
function Host:sync()
    local d=self.drawer
    local stack={}
    for _,entry in ipairs(d.inline_stack or {}) do
        if entry.panel and entry.panel.kind=="menu" then stack[#stack+1]=entry.panel.items end
    end
    local panel=d.inline_panel
    self.item_table=panel and panel.kind=="menu" and panel.items or nil
    self.item_table_stack=stack
    self.page=d.page
end
function Host:updateItems()
    local d=self.drawer
    if d.closed then return end
    local panel=d.inline_panel
    if panel and panel.kind=="menu" and self.item_table then panel.items=self.item_table end
    if self.page and self.page~=d.page then d.page=self.page end
    d:update(); d:refresh()
end
function Host:backToUpperMenu()
    local d=self.drawer
    if d.inline_panel and d.inline_panel.kind=="menu" then d:backInline() end
end
function Host:closeMenu() if not self.drawer.closed then self.drawer:closeDialog() end end
function Host:onInput(input) return self.drawer:onInput(input) end
function Host:showHelp(item)
    local help_text=item.help_text_func and item.help_text_func(self) or item.help_text
    if help_text then self.drawer:showInfo(Items.ucfirst(Items.splitLabel(Items.text(item))),help_text) end
end
Items.install(Host)
function M:menuHost()
    if not self.menu_host then
        self.menu_host=setmetatable({drawer=self,item_table_stack={},page=1},Host)
    end
    return self.menu_host
end
-- Display data and columns of a menu row, computed when rows are built. Paint and
-- tap read the same columns, so the switch zone always matches the drawing.
function M:menuRow(item)
    local desc=Items.describe(item)
    local cols={right=desc.chevron and 690 or 720}
    if desc.kind~="radio" then
        cols.label_limit=cols.right
        if desc.switch~=nil then
            cols.switch_left,cols.switch_right=cols.right-70,cols.right
            cols.label_limit=cols.switch_left
        elseif desc.value then
            cols.value_w=math.min(300,Drawer.measure(self,desc.value,19))
            cols.label_limit=cols.right-cols.value_w-16
        end
    end
    return desc,cols
end
-- One KOReader item as a drawer row (row.desc, row.cols): radio mark, label, value or switch, chevron.
function M:paintMenuRow(bb,row,y,height)
    local desc,cols=row.desc,row.cols
    local mid=y+height/2
    if desc.kind=="radio" then
        self:text(bb,desc.on and "✓" or "○",48,mid,23,true,false,nil,true)
        self:text(bb,desc.label or "",90,mid,21,false,desc.on,620,true)
    else
        if desc.chevron then self:text(bb,"›",715,mid,30,true,false,nil,true) end
        if cols.switch_left then
            Drawer.icon(self,bb,desc.switch and "switch-on" or "switch-off",cols.switch_right-30,mid+self.top/self.scale,58)
        elseif cols.value_w then
            self:text(bb,desc.value,cols.right-cols.value_w,mid,19,false,false,300,true)
        end
        self:text(bb,desc.label or "",30,mid,21,false,true,math.max(40,cols.label_limit-40),true)
    end
    if not desc.enabled then self:text(bb,"—",715,y+height-24,18,true) end
end
function M:menuRowTap(item,cols,x,hold)
    local host=self:menuHost()
    if not Items.enabled(item) then
        if hold then host:showHelp(item) end
        return true
    end
    if hold then host:onMenuHold(item) return true end
    local on_switch=cols.switch_left~=nil and x>=cols.switch_left and x<cols.switch_right
    host:onMenuSelect(item,on_switch)
    return true
end
return M
