-- Independent reader quick actions, without ConfigDialog state.
local Drawer = require("drawer")
local Device = require("device")
local UIManager = require("ui/uimanager")
local Event = require("ui/event")
local BB = require("ffi/blitbuffer")
local tr = require("l10n").tr
local InputContainer = require("ui/widget/container/inputcontainer")
local GestureRange = require("ui/gesturerange")
local M = InputContainer:extend{ modal=false, covers_header=true, covers_footer=true }
function M:init()
    self.dimen=Device.screen:getSize()
    self.scale=self.dimen.w/750
    self.offset=0; self.images={}
    self.full_refresh=self.owner.settings.full_refresh==true
    self.ges_events={}
    for _,name in ipairs({"tap","hold","pan","pan_release","swipe","multiswipe"}) do
        self.ges_events["Quick_"..name]={GestureRange:new{ges=name,range=self.dimen}}
    end
    self.key_events.Close={{"Back"}}
end
function M:showLayoutPanel()
    self.owner:openQuickActionsLayout()
end
function M:closeDialog()
    UIManager:close(self)
    return true
end
function M:onClose() return self:closeDialog() end
function M:onCloseWidget()
    for _,image in pairs(self.images) do image:free() end
    self.images={}
    if self.owner.quick_actions_panel==self then self.owner.quick_actions_panel=nil end
    UIManager:setDirty(nil,self.full_refresh and "full" or "partial",self.dimen)
end
function M:onQuick_tap(_,ges) return self:bookTap(ges.pos) end
function M:onQuick_swipe(_,ges)
    if ges.direction=="south" then
        local pos=ges.pos or ges.start_pos
        if pos and pos.y/self.scale<182 and self.owner.settings.enabled~=false then
            return self.owner:onKindleDrawer()
        end
        return self:closeDialog()
    end
    return true
end
function M:onQuick_hold() return true end
function M:onQuick_pan() return true end
function M:onQuick_pan_release() return true end
function M:onQuick_multiswipe() return true end
function M:text(bb,...) return Drawer.text(self,bb,...) end
function M:rect(bb,x,y,w,h,color)
    bb:paintRect(math.floor(x*self.scale),math.floor(y*self.scale),
        math.max(1,math.floor(w*self.scale)),math.max(1,math.floor(h*self.scale)),color or BB.COLOR_BLACK)
end
function M:bookAction(event)
    local ui=self.ui
    self:closeDialog()
    if event=="Home" and ui.simpleui and ui.simpleui.onSimpleUIGoHomescreen then
        -- PluginLoader wraps handlers in callable tables, so don't require
        -- type(handler) == "function" here.
        ui:handleEvent(Event:new("SimpleUIGoHomescreen"))
        return true
    end
    ui:handleEvent(Event:new(event))
    if event=="Home" then
        local FileManager=require("apps/filemanager/filemanager")
        if FileManager.instance then FileManager.instance:onHome() end
    end
    return true
end
function M:bookProgress()
    local total=tonumber(self.document:getPageCount()) or 0
    local page=tonumber(self.ui:getCurrentPage()) or 0
    if total~=total or total<1 or page~=page then return 0,0,0 end
    page=math.max(1,math.min(total,page))
    return page,total,page/total
end
function M:paintTo(bb)
    local h=self.dimen.h/self.scale
    self:rect(bb,0,0,750,182,BB.COLOR_WHITE)
    self:rect(bb,0,h-142,750,142,BB.COLOR_WHITE)
    self:text(bb,os.date("%H:%M"),26,20,22)
    Drawer.icon(self,bb,"book-chevron",375,37,56)
    -- Battery helper calls text/icon through this instance; home top is zero.
    self.power=Device:getPowerDevice()
    Drawer.paintBattery(self,bb,true)
    Drawer.icon(self,bb,"book-back",34,79,27)
    self:text(bb,tr("Home"),57,65,22,false,false,210)
    self:text(bb,"Aa",425,65,25,true,false,70)
    Drawer.icon(self,bb,"book-toc",500,79,35)
    Drawer.icon(self,bb,"book-bookmark",575,79,35)
    Drawer.icon(self,bb,"book-pages",650,79,35)
    Drawer.icon(self,bb,"book-close",721,79,25)
    self:rect(bb,0,114,750,1,BB.COLOR_LIGHT_GRAY)
    local props=self.ui.doc_props or {}
    local title=props.display_title or props.title or tr("Book")
    self:text(bb,title,26,139,21,false,true,696)
    self:rect(bb,0,179,750,3,BB.COLOR_BLACK)
    local page,total,ratio=self:bookProgress()
    self:rect(bb,0,h-142,750,3,BB.COLOR_BLACK)
    self:text(bb,total>0 and (tr("Page").." "..page.." / "..total) or "—",30,h-120,19,false,false,500)
    self:text(bb,math.floor(ratio*100+0.5).."%",704,h-120,19,true,false,75)
    self:rect(bb,30,h-82,690,5,BB.COLOR_LIGHT_GRAY)
    if ratio>0 then self:rect(bb,30,h-82,690*ratio,5) end
    self:text(bb,tr("Skim document").."  ›",375,h-44,20,true,false,650)
end
function M:bookTap(pos)
    local x,y=pos.x/self.scale,pos.y/self.scale
    if y<45 then
        if x>=330 and x<=420 then self.owner:onKindleDrawer() end
    elseif y<114 then
        if x<270 then return self:bookAction("Home")
        elseif x>=387 and x<463 then self:showLayoutPanel()
        elseif x>=463 and x<538 then return self:bookAction("ShowToc")
        elseif x>=538 and x<613 then return self:bookAction("ShowBookmark")
        elseif x>=613 and x<689 then return self:bookAction("ShowPageBrowser")
        elseif x>=689 then return self:closeDialog() end
    elseif y>=self.dimen.h/self.scale-142 then return self:bookAction("ShowSkimtoDialog")
    elseif y>=182 then return self:closeDialog() end
    return true
end
function M:icon(bb,...) return Drawer.icon(self,bb,...) end
return M
