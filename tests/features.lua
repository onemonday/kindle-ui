local L=require("l10n")
for _,locale in ipairs({"en", "en_US", "de", "fr", "ar"}) do
 G_reader_settings.data.language=locale; assert(L.tr("All Settings")=="All Settings")
end
for _,locale in ipairs({"ru", "ru_RU", "ru-RU"}) do
 G_reader_settings.data.language=locale; assert(L.tr("All Settings")=="Все настройки")
end
G_reader_settings.data.language="en"
local Base=require("ui/widget/container/widgetcontainer")
package.preload["ui/widget/buttondialog"]=function() return Base end
local Dialog=Base:extend{}
function Dialog:onShowKeyboard() end
function Dialog:getInputText() return self.input end
package.preload["ui/widget/inputdialog"]=function() return Dialog end
p4=Plugin:new{ui=newUI()}
for i,event in ipairs({"Restart","RequestSuspend","Exit"}) do
 p4:onKindleDrawer(); p4:activate("power"); assert(not p4.drawer)
 manager.shown.buttons[i][1].callback()
 assert(p4.ui.events[#p4.ui.events]==event)
end
p4:editTitle(); manager.shown.input="My Reader"; manager.shown.buttons[1][2].callback()
assert(G_reader_settings.data.kindle_drawer.title=="My Reader")
p4:editTitle(); manager.shown.input="Wrong"; manager.shown.buttons[1][1].callback()
assert(p4.settings.title=="My Reader")
local running=false; local toggles=0
p4.ui.SSH={isRunning=function() return running end,onToggleSSHServer=function() running=not running; toggles=toggles+1 end}
local found=false
for _,b in ipairs(p4:buttons()) do if b.id=="ssh" then found=true end end
assert(not found, "SSH is opt-in")
p4.settings.hidden.ssh=false
found=false; for _,b in ipairs(p4:buttons()) do if b.id=="ssh" then found=true end end
assert(found)
p4:activate("ssh"); assert(running)
p4:activate("ssh"); assert(not running and toggles==2)
p4.ui.SSH=nil; assert(not p4:available("ssh"))
local items={}; p4:addToMainMenu(items)
local ssh_item=items.kindle_drawer.sub_item_table[3].sub_item_table[2].sub_item_table[6]
ssh_item.callback(); assert(p4.settings.hidden.ssh==true)
ssh_item.callback(); assert(p4.settings.hidden.ssh==false)
p4:onCloseWidget()
print("PASS: locale fallback, Power events, title save/cancel, SSH opt-in and start/stop toggle")

-- Both states have distinct icon assets; action buttons keep their outline.
G_reader_settings.data={language="en"}; screen.w=1072; screen.h=1448
device.wifi=true; device.frontlight=true; device.warm=true
local p=Plugin:new{ui=newUI()}; p.settings.hidden.ssh=false
local ssh_running=false
p.ui.SSH={isRunning=function() return ssh_running end}
p:onKindleDrawer()
local function hasImage(name)
 for _,v in ipairs(painted) do
  if v.kind=="image" and v.file:sub(-#name-5)=="/"..name..".svg" then return true end
 end
 return false
end
for _,state in ipairs({false,true,false}) do
 network.on=state; G_reader_settings.data.night_mode=state; screen.night_mode=state
 power.intensity=state and 12 or 0; ssh_running=state; painted={}
 p.drawer:paintTo(bb)
 for _,id in ipairs({"wifi","night","light","ssh"}) do
  assert(hasImage(id .. (state and "-active" or "")))
 end
 assert(hasImage("settings") and not hasImage("settings-active"))
 for _,v in ipairs(painted) do
  if v.kind=="text" then assert(v.text~="On" and v.text~="Off") end
 end
end
local oldCapacity=power.getCapacity
for _,value in ipairs({0,1,25,57,100,-5,140}) do
 power.getCapacity=function() return value end; painted={}; p.drawer:paintBattery(bb)
 local clamped=math.max(0,math.min(100,value))
 assert(painted[1].text==clamped.."%")
 assert(#painted==(clamped>0 and 5 or 4))
 if clamped>0 then assert(painted[5].w==math.max(1,math.floor(21*clamped/100*p.drawer.scale))) end
end
power.getCapacity=function() return nil end; painted={}; p.drawer:paintBattery(bb)
assert(painted[1].text=="—" and #painted==4)
power.getCapacity=oldCapacity; p:onCloseWidget()
print("PASS: themed toggle variants, no On/Off, battery empty/partial/full/clamped/unknown")

-- The two options are independent; opening and every close path use the chosen refresh.
for _,dim in ipairs({false,true}) do
 for _,full in ipairs({false,true}) do
  G_reader_settings.data={kindle_drawer={dim_background=dim,full_refresh=full}}
  local q=Plugin:new{ui=newUI()}; q:onKindleDrawer(); local d=q.drawer
  assert(manager.last_show.refresh==(full and "full" or "ui"))
  assert(manager.last_show.region.h==screen.h)
  painted={}; d:paintBackground(bb)
  if dim then
   local rows=d.shade_rows
   assert(rows.h==6 and #rows.pixels==math.ceil(screen.w/3) and rows.background.alpha==0)
   for _,px in ipairs(rows.pixels) do assert(px.y==(math.floor(px.x/3)%2)*3 and px.h==3 and px.w==math.min(3,screen.w-px.x)) end
   for _,v in ipairs(painted) do assert(v.y>=d.height and v.y+v.h<=screen.h) end
   d:paintBackground(bb); assert(d.shade_rows==rows, "reuse cached strip")
   screen.night_mode=not screen.night_mode; d:paintBackground(bb)
   assert(rows.freed and d.shade_rows~=rows)
  else assert(#painted==0 and not d.shade_rows) end
  local rows=d.shade_rows
  d:onClose()
  assert(not q.drawer and (not rows or rows.freed))
  assert(manager.last_dirty.refresh==(full and "full" or "partial"))
  assert(manager.last_dirty.region.h==screen.h)
  q:onCloseWidget()
 end
end
G_reader_settings.data={}; local q=Plugin:new{ui=newUI()}; local items={}; q:addToMainMenu(items)
local options=items.kindle_drawer.sub_item_table
assert(options[3].sub_item_table[4].checked_func() and not options[7].checked_func())
options[3].sub_item_table[4].callback(); options[7].callback()
assert(q.settings.dim_background==false and q.settings.full_refresh==true)
q:onKindleDrawer(); q:onSuspend(); assert(manager.last_dirty.refresh=="full")
q:onCloseWidget()
print("PASS: stipple bounds/cache/alpha/cleanup, independent options, full-screen open/close refresh")

G_reader_settings.data={}; local q=Plugin:new{ui=newUI()}; q:onKindleDrawer()
for _,night in ipairs({false,true}) do
 screen.night_mode=night
 for _,charging in ipairs({false,true,false}) do
  power.charging=charging; painted={}; q.drawer:paintBattery(bb)
  assert(painted[1].text=="69%")
  local bolt=false
  for _,item in ipairs(painted) do
   if item.kind=="image" and item.file:find("charging.svg",1,true) then bolt=true end
  end
  assert(bolt==charging)
 end
end
q.drawer:onCharging(); assert(manager.last_dirty.refresh=="ui")
q.drawer:onNotCharging(); assert(manager.last_dirty.refresh=="ui")
q:onCloseWidget(); power.charging=false
print("PASS: charging bolt toggles in both themes; power events request ordinary UI refresh")

G_reader_settings.data={}; local q=Plugin:new{ui=newUI()}; q:onKindleDrawer()
local d=q.drawer; local warm=d.sliders[2]
assert(warm.max==24)
for step=0,24 do
 d:adjust(warm,90+570*step/24)
 assert(power.warmth==math.floor(step*100/24+0.5))
 assert(d:value(warm)==step, "warmth step must survive API round trip")
end
power.warmth=50; d:adjust(warm,700); assert(d:value(warm)==13)
d:adjust(warm,50); assert(d:value(warm)==12)
-- Check each label shares its horizontal center with the corresponding knob.
local text,icon=d.text,d.icon
for _,level in ipairs({0,7,21,24}) do
 power.intensity=level; power.warmth=math.floor(level*100/24+0.5)
 local labels,knobs={},{}
 d.text=function(self,bb,value,x,y,size,centered,bold,max_width)
  for _,slider in ipairs(self.sliders) do
   if y==slider.y+55 then labels[#labels+1]={x=x,value=value} end
  end
 end
 d.icon=function(self,bb,id,x,y,size,active)
  if id=="knob" then knobs[#knobs+1]=x end
 end
 d:paintTo(bb)
 assert(#labels==2 and #knobs==2)
 for i=1,2 do assert(labels[i].x==knobs[i] and labels[i].value==tostring(level)) end
end
d.text=text; d.icon=icon; q:onCloseWidget()
print("PASS: all 25 warmth levels round-trip, +/- steps, moving labels at endpoints and intermediate values")

-- Holding a button opens its own settings instead of toggling it.
G_reader_settings.data={kindle_drawer={hidden={ssh=false}}}; device.wifi=true; device.frontlight=true
function manager:forceRePaint() end
local lights=0; function device:showLightDialog() lights=lights+1 end
package.preload["ui/widget/networksetting"]=function() return Base end
local h=Plugin:new{ui=newUI()}; h.ui.SSH={isRunning=function() return false end}
h.settings.kindle_menu=false -- stock TouchMenu path; tests/menu.lua covers the Kindle-style one
local menu=h.ui.menu
local sync_item={id="progress_sync",text="Progress sync",sub_item_table={{text="Server"}}}
local ssh_item={id="ssh",text="SSH server",sub_item_table={{text="Port"}}}
local more_tools={id="more_tools",text="More tools",sub_item_table={{text="Other"},ssh_item}}
-- Like MenuSorter: placed items leave menu_items and carry their key as id.
menu.menu_items={}
function menu:setUpdateItemTable() self.tab_item_table={{{text="Settings"}},{sync_item,more_tools}} end
function menu:onShowMenu(tab,do_not_show)
 self.shown_tab=tab; self.selected={}
 local touch={}; function touch.onMenuSelect(_,item) self.selected[#self.selected+1]=item end
 self.menu_container={touch}
 if not do_not_show then manager:show(self.menu_container) end
end
local function hold(id)
 h:onKindleDrawer(); local d=h.drawer
 for _,t in ipairs(d.targets) do if t.button.id==id then
  d:onDrawer_hold(nil,{pos={x=d.offset+t.x*d.scale,y=t.y*d.scale}}); return
 end end
 error("no button "..id)
end
network.on=true; local toggled=false
network.toggleWifiOff=function() toggled=true end
network.getNetworkList=function() return {{ssid="a",signal_quality=6},{ssid="b",signal_quality=81}} end
hold("wifi"); assert(not h.drawer and network.on and not toggled)
assert(manager.shown.network_list[1].ssid=="b", "strongest network first")
network.getNetworkList=function() return nil end
hold("wifi"); assert(manager.shown.text=="This device cannot list Wi-Fi networks.")
network.on=false; local long_press
network.toggleWifiOn=function(_,_,lp,interactive) long_press=lp and interactive; network.on=true end
hold("wifi"); assert(long_press==true, "Wi-Fi off uses KOReader's long-press scan")
hold("light"); assert(lights==1 and not h.drawer and power.intensity>0)
hold("sync"); assert(menu.shown_tab==2 and #menu.selected==1 and menu.selected[1]==sync_item)
assert(manager.shown==menu.menu_container and not h.drawer)
hold("ssh"); assert(menu.shown_tab==2 and menu.selected[1]==more_tools and menu.selected[2]==ssh_item)
local night=G_reader_settings.data.night_mode; local events=#h.ui.events
hold("night"); assert(h.drawer and #h.ui.events==events and G_reader_settings.data.night_mode==night)
h:closeDrawer(); ssh_item.id=nil
hold("ssh"); assert(menu.shown_tab==nil and manager.shown==menu.menu_container, "missing item falls back to menu")
manager.shown=nil; hold("settings"); assert(manager.shown==menu.menu_container and not h.drawer)
h:onCloseWidget()
print("PASS: hold opens network list, light dialog, KOSync/SSH submenus; Dark Mode ignores hold")
