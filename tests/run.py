"""Headless Lua checks with device/UI doubles; no Kindle hardware required."""
from pathlib import Path
from lupa.lua51 import LuaRuntime
lua = LuaRuntime(unpack_returned_tuples=True)
# Real Unicode case mapping stands in for KOReader's ffi/utf8proc.
lua.globals().py_upper = lambda s: s.upper()
lua.globals().py_lower = lambda s: s.lower()
lua.execute(r'''
package.path = "kindle-drawer.koplugin/?.lua;" .. package.path
local Base = {}
function Base:extend(t) t=t or {}; t.__index=t; return setmetatable(t,{__index=self}) end
function Base:new(t) t=setmetatable(t or {},{__index=self}); t.key_events={}; if t.init then t:init() end; return t end
package.preload["ui/widget/container/widgetcontainer"] = function() return Base end
package.preload["ui/widget/container/inputcontainer"] = function() return Base end
package.preload["ui/geometry"] = function() return Base end
package.preload["ui/gesturerange"] = function() return Base end
-- gettext returns the msgid, like an untranslated KOReader; logger records lines for assertions.
package.preload["gettext"] = function() return setmetatable({pgettext=function(_,s) return s end},{__call=function(_,s) return s end}) end
log_lines = {}
package.preload["logger"] = function()
 local function rec(level) return function(...) local t={level}; for _,v in ipairs({...}) do t[#t+1]=tostring(v) end; log_lines[#log_lines+1]=table.concat(t," ") end end
 return {dbg=function() end, info=rec("info"), warn=rec("warn"), err=rec("err")}
end
package.preload["ffi/util"] = function() return {template=function(s,...) local a={...}; return (s:gsub("%%(%d)",function(i) return tostring(a[tonumber(i)]) end)) end} end
package.preload["ui/menusorter"] = function() return dofile("tests/menusorter_fake.lua") end
G_reader_settings = { data={} }
function G_reader_settings:readSetting(k,d) if self.data[k]~=nil then return self.data[k] end; return d end
function G_reader_settings:saveSetting(k,v) self.data[k]=v end
function G_reader_settings:isTrue(k) return self.data[k]==true end
power = { fl_min=0, fl_max=24, intensity=12, warmth=50 }
function power:frontlightIntensity() return self.intensity end
function power:frontlightWarmth() return self.warmth end
function power:setIntensity(v) assert(v>=0 and v<=24); self.intensity=v end
function power:setWarmth(v) assert(v>=0 and v<=100); self.warmth=v end
function power:isCharging() return self.charging == true end
function power:getCapacity() return 69 end
function power:isFrontlightOn() return self.intensity>0 end
function power:toggleFrontlight() self.intensity=self.intensity>0 and 0 or 12 end
screen={ w=1072,h=1448 }
function screen:scaleBySize(size) return math.floor(size * (self.dpi_scale or 2) + 0.5) end
function screen:getSize() return {x=0,y=0,w=self.w,h=self.h} end
device={screen=screen,frontlight=true,warm=true,wifi=true}
function device:canRestart() return true end
function device:canSuspend() return true end
function device:getPowerDevice() return power end
function device:hasFrontlight() return self.frontlight end
function device:hasNaturalLight() return self.warm end
function device:hasWifiToggle() return self.wifi end
package.preload.device=function() return device end
manager={}
function manager:show(w,refresh,region) self.shown=w; self.last_show={refresh=refresh,region=region} end
function manager:close(w) if w.onCloseWidget then w:onCloseWidget() end; if self.shown==w then self.shown=nil end end
function manager:setDirty(w,refresh,region) self.last_dirty={widget=w,refresh=refresh,region=region} end
package.preload["ui/uimanager"]=function() return manager end
package.preload["ui/event"]=function() return {new=function(_,name) return {name=name} end} end
package.preload.dispatcher=function() return {registerAction=function() end} end
network={on=false}
function network:isWifiOn() return self.on end
function network:toggleWifiOn() self.on=true end
function network:toggleWifiOff() self.on=false end
package.preload["ui/network/manager"]=function() return network end
package.preload["ui/widget/infomessage"]=function() return Base end
package.preload["ui/font"]=function() return {getFace=function(_,_,size) return screen:scaleBySize(size) end} end
package.preload["ffi/blitbuffer"]=function()
 return {COLOR_BLACK="black",COLOR_WHITE="white",COLOR_LIGHT_GRAY="#ccc",TYPE_BB8A=1,
 COLOR_GRAY_3="#333",COLOR_GRAY_5="#555",COLOR_GRAY_9="#999",COLOR_GRAY_D="#ddd",COLOR_GRAY="#aaa",COLOR_DARK_GRAY="#888",
 Color8A=function(v,a) return {value=v,alpha=a} end,
 new=function(w,h,t)
  local b={w=w,h=h,t=t,pixels={},background={value=0,alpha=0}}
  function b:fill(v) self.background=v end
  function b:paintRect(x,y,rw,rh,c) assert(x+rw<=self.w and y+rh<=self.h); self.pixels[#self.pixels+1]={x=x,y=y,w=rw,h=rh,c=c}; self.ink=c end
  function b:free() self.freed=true end
  return b
 end}
end
painted={}
local Text=Base:extend{}
function Text:getSize() return {w=#self.text*self.face*0.28,h=self.face} end
function Text:paintTo(bb,x,y) painted[#painted+1]={kind="text",text=self.text,x=x,y=y,size=self.face,bold=self.bold,color=self.fgcolor} end
function Text:isTruncated() return self.max_width~=nil and #self.text*self.face*0.28>self.max_width end
function Text:free() end
package.preload["ui/widget/textwidget"]=function() return Text end
local Image=Base:extend{}
function Image:paintTo(bb,x,y) assert(self.alpha == true, "SVG must alpha blend"); assert(self.original_in_nightmode == false, "UI icons must follow whole-screen inversion"); painted[#painted+1]={kind="image",file=self.file,x=x,y=y,w=self.width,h=self.height} end
function Image:free() end
package.preload["ui/widget/imagewidget"]=function() return Image end
bb={paintRect=function(_,x,y,w,h,color) painted[#painted+1]={kind="rect",x=x,y=y,w=w,h=h,color=color} end}
function bb:alphablitFrom(source,x,y,ox,oy,w,h)
 assert(ox==0 and oy==0 and h<=source.h and w==source.w)
 painted[#painted+1]={kind="shade",x=x,y=y,w=w,h=h,color=source.ink}
end
function device:isTouchDevice() return self.touch ~= false end
package.preload["ffi/utf8proc"]=function() return {uppercase_dumb=function(s) return py_upper(s) end,lowercase=function(s) return py_lower(s) end} end
clock_ms=0
package.preload["ui/time"]=function() return {now=function() return clock_ms*1000 end,to_ms=function(t) return t/1000 end} end
package.preload.datetime=function() return {secondsToHour=function(s,twelve) return os.date(twelve and "%I:%M %p" or "%H:%M",s) end} end
function manager:scheduleIn(_,fn) self.scheduled=fn end
function manager:unschedule(fn) if self.scheduled==fn then self.scheduled=nil end end
function newUI()
 local menu={activation_menu="swipe_tap",original_calls=0}
 function menu:registerToMainMenu() end
 function menu:setUpdateItemTable() self.tab_item_table={{icon="appbar.settings",{text="item"}}} end
 function menu:onShowMenu() self.original_calls=self.original_calls+1 end
 function menu:onTapShowMenu() self.original_calls=self.original_calls+1 end
 function menu:onSwipeShowMenu() self.original_calls=self.original_calls+1 end
 function menu:onCloseFileManagerMenu()
  if self.menu_container then manager:close(self.menu_container); self.menu_container=nil end
  return true
 end
 local ui={menu=menu,document={},kosync={},events={}}
 function ui:handleEvent(e) self.events[#self.events+1]=e.name end
 return ui
end
Plugin=require("main")
ui=newUI(); original=ui.menu.onTapShowMenu; plugin=Plugin:new{ui=ui}
assert(ui.menu:onSwipeShowMenu({direction="south"})==true and plugin.drawer)
assert(ui.menu.original_calls==0)
local first=plugin.drawer; plugin:onKindleDrawer(); assert(first==plugin.drawer)
plugin:activate("settings"); assert(not plugin.drawer and plugin.settings_menu and ui.menu.original_calls==0)
plugin:onKindleDrawer(); assert(plugin.drawer and not plugin.settings_menu, "panels are mutually exclusive")
plugin.settings.kindle_menu=false
plugin:activate("settings"); assert(not plugin.drawer and not plugin.settings_menu and ui.menu.original_calls==1)
plugin.settings.kindle_menu=nil
plugin:onKindleDrawer(); local d=plugin.drawer
assert(d.height<screen.h and #d.sliders==2)
d:paintTo(bb)
for _,v in ipairs(painted) do if v.kind=="text" then
 assert(math.abs(v.size - 23*d.scale) <= 1, "Font DPI must only apply once"); break end end
d:adjust(d.sliders[1],-100); assert(power.intensity==11)
d:adjust(d.sliders[1],660); assert(power.intensity==24)
d:adjust(d.sliders[1],700); assert(power.intensity==24)
d:adjust(d.sliders[2],90); assert(power.warmth==0)
d:adjust(d.sliders[2],660); assert(power.warmth==100)
local old=power.intensity
local track={x=d.offset+375*d.scale,y=(d.sliders[1].y+90)*d.scale}
d:onDrawer_pan(nil,{start_pos={x=track.x,y=d.height-10},pos=track})
assert(power.intensity==old, "closing drag must not change light")
d:onDrawer_pan_release(nil,{pos=track})
d:onDrawer_pan(nil,{start_pos=track,pos={x=d.offset+90*d.scale,y=track.y}})
assert(power.intensity==0)
d:onDrawer_pan_release(nil,{pos={x=d.offset+660*d.scale,y=track.y}})
assert(power.intensity==24)
d:onDrawer_pan(nil,{start_pos=track,pos=track})
d:onDrawer_multiswipe(); assert(d.drag_slider==nil)
local previous=power.intensity
d:onDrawer_pan(nil,{start_pos={x=track.x,y=d.height-10},pos=track})
assert(power.intensity==previous)
d:onDrawer_multiswipe()
d:onDrawer_tap(nil,{pos={x=0,y=screen.h-1}}); assert(not plugin.drawer)
for _,id in ipairs({"wifi","night","sync","light","power","ssh"}) do plugin.settings.hidden[id]=true end
assert(#plugin:buttons()==1 and plugin:buttons()[1].id=="settings")
plugin.settings.enabled=false; plugin.settings.quick_actions_enabled=false
ui.menu:onTapShowMenu({}); assert(ui.menu.original_calls==1 and plugin.settings_menu); plugin:closeSettingsMenu()
plugin.settings.kindle_menu=false; ui.menu:onTapShowMenu({}); assert(ui.menu.original_calls==2); plugin.settings.kindle_menu=nil
plugin.settings.enabled=true; ui.menu:onSwipeShowMenu({direction="south"}); assert(plugin.drawer)
plugin:onSuspend(); assert(not plugin.drawer)
plugin:onCloseWidget(); assert(ui.menu.onTapShowMenu==original)
G_reader_settings.data={}; device.frontlight=false; device.warm=false; device.wifi=false
ui2=newUI(); ui2.document=nil; ui2.kosync=nil
p2=Plugin:new{ui=ui2}; p2:onKindleDrawer(); assert(#p2.drawer.sliders==0 and #p2:buttons()==3)
p2:onCloseWidget()
-- Geometry also fits landscape.
device.frontlight=true; device.warm=true; screen.w=1448; screen.h=1072
p3=Plugin:new{ui=newUI()}; p3:onKindleDrawer(); assert(p3.drawer.height<screen.h)
p3:onCloseWidget()
''')
preview_paint = lua.globals().painted
lua.execute(Path('tests/features.lua').read_text())
lua.execute(Path('tests/menu.lua').read_text())
lua.execute(Path('tests/layout.lua').read_text())
print('PASS: Lua load, menu hooks/restore, all-settings escape, toggle visibility, capability filtering, slider bounds, dismissal, suspend, portrait/landscape fit')
# Approximate visual artifact from actual paint calls; font metrics are doubles.
from html import escape
parts = ['<svg xmlns="http://www.w3.org/2000/svg" width="1072" height="1448" viewBox="0 0 1072 1448"><rect width="1072" height="1448" fill="#eee"/>']
parts.append('<defs><pattern id="shade" width="6" height="6" patternUnits="userSpaceOnUse"><rect width="3" height="3" fill="black"/><rect x="3" y="3" width="3" height="3" fill="black"/></pattern></defs>')
for item in preview_paint.values():
    k=item['kind']; x=item['x']; y=item['y']
    if k=='rect': parts.append(f'<rect x="{x}" y="{y}" width="{item["w"]}" height="{item["h"]}" fill="{item["color"]}"/>')
    elif k=='text': parts.append(f'<text x="{x}" y="{y+item["size"]}" font-family="sans-serif" font-size="{item["size"]}" font-weight="{700 if item["bold"] else 400}">{escape(item["text"])}</text>')
    elif k=='shade':
        parts.append(f'<rect x="{x}" y="{y}" width="{item["w"]}" height="{item["h"]}" fill="url(#shade)"/>')
    else:
        import base64
        data=base64.b64encode(Path(item['file']).read_bytes()).decode()
        parts.append(f'<image x="{x}" y="{y}" width="{item["w"]}" height="{item["h"]}" href="data:image/svg+xml;base64,{data}"/>')
parts.append('</svg>')
Path('dist/preview.svg').write_text(''.join(parts))
