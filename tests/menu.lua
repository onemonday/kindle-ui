-- Kindle-style top menu: hooks, item mapping, TouchMenu-compatible callbacks, scrolling.
local SM=require("settingsmenu")
local Base=require("ui/widget/container/widgetcontainer")
package.preload["ui/widget/infomessage"]=function() return Base end
G_reader_settings.data={language="en"}; screen.w=1072; screen.h=1448; device.touch=true
device.wifi=true; network.on=true

-- display-only capitalization
local U=SM.ucfirst
assert(U("name")=="Name" and U("Name")=="Name" and U("")=="" and U("123 pages")=="123 pages")
assert(U("привет")=="Привет" and U("ёлка")=="Ёлка" and U("Привет")=="Привет")
assert(U("eReader")=="eReader" and U("iOS")=="iOS" and U("éclair")=="Éclair")
assert(U("x")=="X")
local l,v=SM.splitLabel("Sort by: name"); assert(l=="Sort by" and v=="name")
l,v=SM.splitLabel("Plain"); assert(l=="Plain" and v==nil)
l,v=SM.splitLabel("Time: 12:30"); assert(l=="Time" and v=="12:30")
print("PASS: ucfirst Latin/Cyrillic/eReader/iOS, Label: value split")

-- Fake KOReader menu with MenuSorter-shaped tabs.
local state, calls
local function newMenuUI(document)
 local ui=newUI(); ui.document=document
 local menu=ui.menu
 function menu:onPressMenu() self.original_calls=self.original_calls+1 end
 function menu:onRebuildMenu() self.rebuilds=(self.rebuilds or 0)+1; self.tab_item_table=nil end
 function menu:onCloseFileManagerMenu()
  if not self.menu_container then return true end
  self.saved_tab=self.menu_container[1].last_index
  manager:close(self.menu_container); self.menu_container=nil; return true
 end
 function menu:setUpdateItemTable()
  local function radio(text,n) return {text=text,radio=true,checked_func=function() return state.radio==n end,callback=function() state.radio=n end} end
  local files={icon="appbar.filebrowser",id="filemanager_settings"}
  files[1]={text="Display mode",sub_item_table={radio("classic (filename only)",1),radio("mosaic with cover images",2)}}
  files[2]={text_func=function() return "Sort by: "..state.sort end,separator=true,
   sub_item_table={radio("name",1),radio("date",2)}}
  files[3]={text="Reverse sorting",checked_func=function() return state.reverse end,callback=function(tm) calls.reverse_tm=tm; state.reverse=not state.reverse end}
  files[4]={id="sort_mixed",text="Folders and files mixed",checked_func=function() return false end,callback=function() end}
  files[5]={id="start_with",text="Start with: file browser",sub_item_table={radio("file browser",1)}}
  files[6]={text="Disabled thing",enabled_func=function() return false end,callback=function() calls.disabled=true end,help_text="Help!"}
  files[7]={text="Mandatory",mandatory_func=function() return "42" end,keep_menu_open=true,
   callback=function(tm) calls.keep=tm end,hold_callback=function(tm,item) calls.hold={tm,item} end}
  files[8]={text="Replace items",keep_menu_open=true,callback=function(tm)
   tm.item_table={{text="fresh item"},{text="second"}}; tm.page=1; tm:updateItems() end}
  files[9]={text="Close me",callback=function(tm) calls.close_tm=tm end}
  files[10]={text="A very long label that certainly does not fit in one line of the Kindle menu, not even on the smaller design scale",sub_item_table_func=function()
   return {{text="up",keep_menu_open=true,callback=function(tm) tm:backToUpperMenu() end}} end}
  -- Switch and chevron on one row, like readerfont.lua font family items.
  files[11]={text="Font family",checked_func=function() return true end,
   checkmark_callback=function() calls.checkmark=(calls.checkmark or 0)+1 end,sub_item_table={{text="family font"}}}
  files[12]={text="Wireless",enabled_func=function() return state.connected end,keep_menu_open=true,
   callback=function() calls.wireless=(calls.wireless or 0)+1 end}
  files[13]={text_func=function() return "Device: "..string.rep("very long value ",8) end,keep_menu_open=true,callback=function() end}
  local general={icon="appbar.settings",id="setting"}
  for i=1,30 do general[i]={text="option "..i,keep_menu_open=true,callback=function() end} end
  general[5].separator=true
  local tools={icon="appbar.tools",id="tools"}
  local items={}; self.plugin:addToMainMenu(items); items.kindle_drawer.id="kindle_drawer"
  tools[1]={id="more_tools",text="More tools",sub_item_table={{text="Calculator",callback=function() end},items.kindle_drawer}}
  local reader={icon="book.opened",id="reader",remember=false,callback=function() calls.reader=true; menu:onCloseFileManagerMenu() end}
  local unknown={icon="weird.icon",id="mystery",{text="x"}}
  self.tab_item_table={files,general,tools,reader,unknown}
 end
 return ui
end
local function reset() state={radio=2,sort="name",reverse=false}; calls={} end
reset()

-- hook install / restore
local ui=newMenuUI(nil); local menu=ui.menu
local originals={}
for _,name in ipairs({"onTapShowMenu","onSwipeShowMenu","onPressMenu","onShowMenu","onRebuildMenu"}) do originals[name]=menu[name] end
local p=Plugin:new{ui=ui}; menu.plugin=p
for name,fn in pairs(originals) do assert(menu[name]~=fn, name.." hooked") end

-- setting off, non-touch, do_not_show: stock menu
p.settings.kindle_menu=false; menu:onShowMenu(); assert(menu.original_calls==1 and not p.settings_menu)
p.settings.kindle_menu=nil; device.touch=false; menu:onShowMenu(); assert(menu.original_calls==2 and not p.settings_menu)
device.touch=true; menu:onShowMenu(1,true); assert(menu.original_calls==3 and not p.settings_menu)
p.settings.kindle_menu=false; menu:onPressMenu(); assert(menu.original_calls==4); p.settings.kindle_menu=nil
local options; do local t={}; p:addToMainMenu(t); options=t.kindle_drawer.sub_item_table end
assert(options[1].hint=="Replaces the KOReader top menu" and options[1].checked_func() and options[1].separator)
options[1].callback(); assert(p.settings.kindle_menu==false and not options[1].checked_func()); options[1].callback()

-- root page
menu:onShowMenu(); local m=p.settings_menu
assert(m and manager.shown==m and menu.menu_container==m and menu.original_calls==4)
assert(manager.last_show.refresh=="flashui")
assert(m.at_root and #m.rows==5)
local labels={"Files","General","Tools","Continue reading","Menu"}
local icons={"menu-files","menu-general","menu-tools","menu-book","menu-generic"}
for i,row in ipairs(m.rows) do assert(row.kind=="tab" and row.label==labels[i] and row.icon==icons[i] and row.h==56) end
assert(m.rows[1].chevron and not m.rows[4].chevron, "action tab has no chevron")
assert(m:title()=="Settings" and m.max==0)
painted={}; m:paintTo(bb)
local function find(kind,pred) for _,v in ipairs(painted) do if v.kind==kind and pred(v) then return v end end end
assert(find("text",function(v) return v.text=="Continue reading" end))
assert(find("image",function(v) return v.file:find("menu%-book%.svg") end))
assert(not find("image",function(v) return v.file:find("menu%-back%.svg") end), "no back arrow on root")
assert(find("image",function(v) return v.file:find("menu%-wifi%.svg") end))
print("PASS: hooks, setting off / non-touch / do_not_show keep stock menu, root rows from tab_item_table")

-- Files tab: item mapping and value sources
local function tapAt(index,ux)
 local row=m.rows[index]
 return m:onKMenu_tap(nil,{pos={x=(ux or 200)*m.scale,y=(79+row.y-m.offset+row.h/2)*m.scale}})
end
local function holdAt(index)
 local row=m.rows[index]
 return m:onKMenu_hold(nil,{pos={x=100*m.scale,y=(79+row.y-m.offset+20)*m.scale}})
end
tapAt(1); assert(not m.at_root and m.cur_tab==1 and m:title()=="Files")
local r=m.rows
assert(r[1].label=="Display mode" and r[1].chevron and r[1].value=="Mosaic with cover images", "radio parent shows selected child")
assert(r[2].label=="Sort by" and r[2].value=="Name" and r[2].chevron, "Label: value split")
assert(r[3].kind=="sep" and r[3].h==11)
assert(r[4].switch==false and r[4].value==nil and not r[4].chevron, "checkbox is a switch")
assert(r[5].sub=="Folders are sorted together with books" and r[5].h==68, "hint by MenuSorter id")
assert(r[6].label=="Start with" and r[6].value=="File browser" and r[6].sub)
assert(r[7].enabled==false)
assert(r[8].value=="42", "mandatory_func is the value")
assert(m.item_table[1].idx==1 and m.item_table[10].idx==10)
painted={}; m:paintTo(bb)
local dis=find("text",function(v) return v.text=="Disabled thing" end)
assert(dis.color==SM.colors.disabled and not dis.bold, "disabled label is grey")
assert(find("text",function(v) return v.text=="Folders are sorted together with books" and v.color==SM.colors.sub end))
assert(find("text",function(v) return v.text=="42" and v.color==SM.colors.value end))
local gap=find("rect",function(v) return v.color==SM.colors.group end)
assert(gap and gap.x==0 and gap.w>=math.floor((m.max>0 and m.W-46 or m.W)*m.scale)-1, "separator line spans the width up to the scrollbar")
assert(not find("text",function(v) return v.text=="name" end), "values are capitalized")
assert(find("image",function(v) return v.file:find("menu%-back%.svg") end))
assert(find("image",function(v) return v.file:find("switch%-off%.svg") end))

-- disabled rows are not tappable; hold shows help
tapAt(7); assert(not calls.disabled and p.settings_menu==m)
manager.shown=nil
holdAt(7); assert(manager.shown and manager.shown.text=="Help!")
manager.shown=m

-- checkbox: callback gets the menu, view refreshes, menu stays open
tapAt(4); assert(calls.reverse_tm==m and state.reverse and m.rows[4].switch==true and p.settings_menu==m)
-- keep_menu_open and hold_callback
tapAt(8); assert(calls.keep==m and p.settings_menu==m)
holdAt(8); assert(calls.hold[1]==m and calls.hold[2]==m.item_table[7])
-- radio page and parent value
tapAt(1); assert(m:title()=="Display mode" and #m.item_table_stack==1 and m.rows[1].kind=="radio")
assert(m.rows[1].label=="Classic (filename only)" and not m.rows[1].on and m.rows[2].on)
painted={}; m:paintTo(bb)
assert(find("image",function(v) return v.file:find("menu%-radio%-on%.svg") end))
assert(find("text",function(v) return v.text=="Mosaic with cover images" and v.bold end))
assert(find("text",function(v) return v.text=="Classic (filename only)" and not v.bold end))
tapAt(1); assert(state.radio==1 and m.rows[1].on and p.settings_menu==m, "radio stays open and refreshes")
m:onKMenu_tap(nil,{pos={x=20*m.scale,y=54*m.scale}}); assert(m:title()=="Files" and m.rows[1].value=="Classic (filename only)")
-- sub_item_table_func and backToUpperMenu from a callback
local long=m.rows[11]; assert(long.chevron and long.label:sub(1,6)=="A very")
m:scrollTo(1e9); painted={}; m:paintTo(bb); assert(long.truncated, "long label is truncated")
manager.shown=nil
holdAt(11)
assert(manager.shown and manager.shown.text==long.item.text, "hold on a truncated label shows the full text")
manager.shown=m
tapAt(11); assert(#m.item_table_stack==1 and m.rows[1].label=="Up")
tapAt(1); assert(#m.item_table_stack==0 and m:title()=="Files")
-- a callback replacing item_table and page
tapAt(8+1); assert(#m.rows==2 and m.rows[1].label=="Fresh item" and p.settings_menu==m)
m:backToUpperMenu(); assert(m.at_root)
m:openTab(1)
-- an ordinary action closes the menu (no keep_menu_open)
tapAt(10); assert(calls.close_tm==m and not p.settings_menu and m.closed and menu.menu_container==nil)
assert(menu.saved_tab==1, "KOReader saves last tab through menu_container[1]")
print("PASS: submenu/switch/radio/value/mandatory/hint/separator/disabled mapping, touchmenu_instance callbacks, keep_menu_open")

-- action tab runs the callback and closes; onShowMenu(tab) and remember=false
menu:onShowMenu(); m=p.settings_menu; tapAt(4); assert(calls.reader and not p.settings_menu)
menu:onShowMenu(1); m=p.settings_menu; assert(m.cur_tab==1 and m:title()=="Files")
m:backToUpperMenu(); assert(m.at_root and p.settings_menu==m)
m:backToUpperMenu(); assert(not p.settings_menu, "Back on root closes")
calls.reader=nil
menu:onShowMenu(4); m=p.settings_menu; assert(m.at_root and p.settings_menu==m and not calls.reader, "remember=false tab is not auto-run")
m:closeMenu()

-- openMenuItem routes into the new menu
p:openMenuItem("sort_mixed"); m=p.settings_menu
assert(m and m.cur_tab==1 and m:title()=="Files")
p:openMenuItem("kindle_drawer"); assert(p.settings_menu==m and m:title()=="Kindle Drawer" and #m.item_table_stack==2)
assert(m.rows[1].label=="Kindle-style menu" and m.rows[1].sub=="Replaces the KOReader top menu" and m.rows[2].kind=="sep")
m:onBack(); assert(m:title()=="More tools"); m:onBack(); assert(m:title()=="Tools"); m:onBack(); assert(m.at_root)
m:closeMenu()

-- ⋮ popup actions
menu:onShowMenu(2); m=p.settings_menu
m:onKMenu_tap(nil,{pos={x=(m.W-66)*m.scale,y=54*m.scale}}); assert(m.popup)
painted={}; m:paintTo(bb); assert(find("text",function(v) return v.text=="Classic KOReader menu" end))
local before=menu.original_calls
m:onKMenu_tap(nil,{pos={x=(m.W-100)*m.scale,y=(70+20)*m.scale}})
assert(not p.settings_menu and menu.original_calls==before+1, "classic menu bypasses the hook")
menu:onShowMenu(); m=p.settings_menu
m:onKMenu_tap(nil,{pos={x=(m.W-66)*m.scale,y=54*m.scale}})
m:onKMenu_tap(nil,{pos={x=(m.W-100)*m.scale,y=(70+64)*m.scale}})
assert(p.settings_menu==m and m:title()=="Kindle Drawer" and not m.popup)
m:onKMenu_tap(nil,{pos={x=(m.W-66)*m.scale,y=54*m.scale}}); m:onKMenu_tap(nil,{pos={x=10*m.scale,y=400*m.scale}})
assert(not m.popup and p.settings_menu==m, "tap outside closes only the popup")
m:closeMenu()
print("PASS: action tab, onShowMenu(tab) with back to root, remember=false, openMenuItem routing, ⋮ classic/plugin actions")

-- review fixes: switch vs chevron, live enabled_func, truncated value, multiswipe, mouse wheel
reset(); state.connected=true
menu:onShowMenu(1); m=p.settings_menu; m:scrollTo(1e9)
local fam=m.rows[12]; assert(fam.label=="Font family" and fam.switch==true and fam.chevron)
local right=m.W-(m.max>0 and 58 or 32)
tapAt(12,right-4.5); assert(not calls.checkmark and m:title()=="Font family", "chevron opens the submenu")
m:onBack(); fam=m.rows[12]
tapAt(12,right-23-25); assert(calls.checkmark==1 and m:title()=="Files", "switch runs checkmark_callback")
local wl=m.rows[13]; assert(wl.enabled)
state.connected=false; tapAt(13,100); assert(not calls.wireless, "enabled_func is evaluated at tap time")
state.connected=true; m:updateItems(); state.connected=false; manager.shown=nil
holdAt(13); assert(not calls.wireless)
state.connected=true; m.rows[13].enabled=false; tapAt(13,100); assert(calls.wireless==1, "stale disabled cache does not block")
local dev=m.rows[14]; assert(dev.label=="Device" and dev.value)
painted={}; m:paintTo(bb); assert(dev.truncated, "a cut value marks the row truncated")
manager.shown=nil
holdAt(14)
assert(manager.shown and manager.shown.text==m.item_table[13].text_func(), "hold shows the whole row text")
manager.shown=m; m:closeMenu()
menu:onShowMenu(2); m=p.settings_menu; m:scrollTo(0)
local px=150*m.scale; local py=400*m.scale
m:onKMenu_pan(nil,{start_pos={x=px,y=py},pos={x=px,y=py-130*m.scale},relative={x=0,y=-130*m.scale},time=5000*1000})
assert(manager.last_dirty.refresh=="fast")
m:onKMenu_multiswipe(nil,{pos={x=px,y=py},end_pos={x=px+200,y=py-130*m.scale},time=5400*1000})
assert(m.offset==112 and not m.drag and manager.last_dirty.refresh=="ui", "multiswipe settles the drag")
m:onPan(nil,{mousewheel_direction=-1,direction="north"}); assert(m.offset==291)
local after=m.offset; m:onPan(nil,{mousewheel_direction=1,direction="south"}); assert(m.offset<after)
m:closeMenu()
print("PASS: switch/chevron hit areas, live enabled_func, truncated value on hold, multiswipe settle, mouse wheel")

-- scrolling: snapping, clamping, last row on the bottom edge, fling, throttled fast refresh
menu:onShowMenu(2); m=p.settings_menu
assert(#m.rows==31 and m.max>0 and m.total==30*56+11)
local last=m.rows[#m.rows]
m:scrollTo(1e9); assert(m.offset==m.max and math.abs(last.y+last.h-m.offset-m.view_h)<1e-6, "last row on the bottom edge")
m:scrollTo(-50); assert(m.offset==0)
m:scrollTo(80); assert(m.offset==56)
m:scrollTo(56*5+11+10); assert(m.offset==56*5+11, "snaps to a row top after a separator")
for _,s in ipairs(m.snaps) do assert(s>=0 and s<=m.max) end
painted={}; m:paintTo(bb)
assert(find("image",function(v) return v.file:find("menu%-down%.svg") end) and find("image",function(v) return v.file:find("menu%-up%.svg") end))
-- rows end before the scrollbar column (58 units vs 32 without scroll)
local dividers=0
for _,v in ipairs(painted) do
 if v.kind=="rect" and v.color==SM.colors.divider and v.h<=3 and v.y>79*m.scale then
  dividers=dividers+1; assert(v.x+v.w<=math.floor((m.W-58)*m.scale)+1)
 end
end
assert(dividers>0)
local thumb=find("rect",function(v) return v.color=="black" and v.w==math.max(1,math.floor((m.W-19)*m.scale)-math.floor((m.W-23)*m.scale)) end)
assert(thumb and thumb.x>=math.floor((m.W-28)*m.scale) and thumb.x+thumb.w<=math.floor((m.W-14)*m.scale)+1, "scrollbar 14-28 units from the edge")
m:scrollTo(0)
-- pan follows the finger, fast refresh of the list region only, throttled
clock_ms=1000; manager.scheduled=nil
local x=150*m.scale; local y0=400*m.scale
m:onKMenu_pan(nil,{start_pos={x=x,y=y0},pos={x=x,y=y0-100*m.scale},relative={x=0,y=-100*m.scale},time=1000*1000})
assert(math.abs(m.offset-100)<1e-6 and manager.last_dirty.refresh=="fast")
assert(manager.last_dirty.region.y==math.floor(79*m.scale) and manager.last_dirty.region.h==screen.h-math.floor(79*m.scale))
manager.last_dirty=nil; clock_ms=1030
m:onKMenu_pan(nil,{start_pos={x=x,y=y0},pos={x=x,y=y0-130*m.scale},relative={x=0,y=-130*m.scale},time=1030*1000})
assert(manager.last_dirty==nil and manager.scheduled, "repaint throttled to 80 ms")
clock_ms=1090; local fire=manager.scheduled; manager.scheduled=nil; fire()
assert(manager.last_dirty.refresh=="fast")
-- finger stopped before lifting: no momentum, snap to nearest row top
m:onKMenu_pan_release(nil,{pos={x=x,y=y0-130*m.scale},time=1300*1000})
assert(m.offset==112 and manager.last_dirty.refresh=="ui" and not manager.scheduled)
-- quick flick ending as swipe: momentum = velocity * 320 ms, then snap
clock_ms=2000
m:onKMenu_pan(nil,{start_pos={x=x,y=y0},pos={x=x,y=y0-20*m.scale},relative={x=0,y=-20*m.scale},time=2000*1000})
m:onKMenu_pan(nil,{start_pos={x=x,y=y0},pos={x=x,y=y0-60*m.scale},relative={x=0,y=-60*m.scale},time=2040*1000})
m:onKMenu_swipe(nil,{direction="north",pos={x=x,y=y0},end_pos={x=x,y=y0-60*m.scale},time=2050*1000})
-- v = 1 unit/ms upwards -> 320 units of momentum: 112+60+320=492, nearest row top
assert(m.offset==m:nearestSnap(492) and m.offset>400, "fling adds momentum")
-- a flick without pan events still scrolls with momentum
local before_flick=m.offset
m:onKMenu_swipe(nil,{direction="north",pos={x=x,y=y0},end_pos={x=x,y=y0-50*m.scale},distance=50*m.scale,time=2600*1000})
assert(m.offset>before_flick+50 and m.offset==m:nearestSnap(m.offset))
m:scrollTo(0)
-- swipe east goes back, like the ← button; swipe down from the header opens the top drawer
m:onKMenu_swipe(nil,{direction="east",pos={x=x,y=y0},end_pos={x=x+300,y=y0}}); assert(m.at_root and p.settings_menu==m)
m:openTab(2)
-- clamped at the end
m:onKMenu_pan(nil,{start_pos={x=x,y=y0},pos={x=x,y=y0-5000*m.scale},relative={x=0,y=-5000*m.scale},time=3000*1000})
m:onKMenu_pan_release(nil,{pos={x=x,y=y0-5000*m.scale},time=3500*1000})
assert(m.offset==m.max)
-- ▲▼ and page keys scroll by one screen minus one row
m:scrollTo(0)
local bar=m:scrollbar()
m:onKMenu_tap(nil,{pos={x=(m.W-21)*m.scale,y=(bar.bottom-9)*m.scale}})
assert(m.offset==m:nearestSnap(m.view_h-56) and m.offset>0)
m:onPrevPage(); assert(m.offset==0)
m:onNextPage(); local page2=m.offset; assert(page2>0 and m.page==2)
-- updateItems() keeps the position; page=1 + updateItems() returns to the top like TouchMenu
m:updateItems(); assert(m.offset==page2)
m.page=1; m:updateItems(); assert(m.offset==0)
-- a pan that starts in the header does not scroll
m:onKMenu_pan(nil,{start_pos={x=x,y=40*m.scale},pos={x=x,y=300*m.scale},relative={x=0,y=260*m.scale}})
assert(m.offset==0); m:onKMenu_pan_release(nil,{pos={x=x,y=300*m.scale}})
m:closeMenu()
print("PASS: continuous scroll, snap to row tops, clamp, last row on bottom edge, fling, 80 ms fast refresh, ▲▼/page keys")

-- mutual exclusion, suspend, dimension change, rebuild, teardown
menu:onShowMenu(); m=p.settings_menu
m:onKMenu_tap(nil,{pos={x=m.W/2*m.scale,y=12*m.scale}}); assert(p.drawer and not p.settings_menu, "chevron opens the top drawer")
p:activate("settings"); assert(p.settings_menu and not p.drawer, "All Settings opens the new menu")
m=p.settings_menu; m:onKMenu_swipe(nil,{direction="south",pos={x=500,y=20},end_pos={x=500,y=400}})
assert(p.drawer and not p.settings_menu, "swipe down from the status bar opens the top drawer")
p:activate("settings")
p:onSuspend(); assert(not p.settings_menu)
-- rotation: ReaderMenu/FileManagerMenu:onSetDimensions reopen the menu themselves; only the drawers close here
menu:onShowMenu(); m=p.settings_menu; p:onSetDimensions(); assert(p.settings_menu==m and not m.closed)
p:onKindleDrawer(); p:onSetDimensions(); assert(not p.drawer and not p.settings_menu)
menu:onShowMenu(1); m=p.settings_menu; tapAt(1)
menu:onRebuildMenu(); assert(menu.rebuilds==1)
local m2=p.settings_menu; assert(m2 and m2~=m and m.closed and m2:title()=="Display mode" and m2.cur_tab==1)
assert(m2.rows[1].kind=="radio")
p:onCloseWidget(); assert(not p.settings_menu and m2.closed)
for name,fn in pairs(originals) do assert(menu[name]==fn, name.." restored") end
-- gestures in the file browser open the root; activation_menu respected
local ui3=newMenuUI(nil); local p3=Plugin:new{ui=ui3}; ui3.menu.plugin=p3
ui3.menu:onTapShowMenu({pos={x=10,y=10}}); assert(p3.settings_menu and p3.settings_menu.at_root); p3:closeSettingsMenu()
p3.settings.enabled=false
ui3.menu:onSwipeShowMenu({direction="south"}); assert(p3.settings_menu and not p3.drawer); p3:closeSettingsMenu()
ui3.menu.activation_menu="swipe"; local calls0=ui3.menu.original_calls
ui3.menu:onTapShowMenu({pos={x=10,y=10}}); assert(not p3.settings_menu and ui3.menu.original_calls==calls0+1)
p3:onCloseWidget()
print("PASS: chevron→drawer, All Settings, suspend/rotation close, rebuild restores page, teardown restores hooks, gestures")

-- landscape keeps mockup row height and the RU strings
G_reader_settings.data={language="ru"}; screen.w=1448; screen.h=1072
local ui4=newMenuUI(nil); local p4=Plugin:new{ui=ui4}; ui4.menu.plugin=p4
ui4.menu:onShowMenu(); m=p4.settings_menu
assert(math.abs(m.scale-1072/683)<1e-9 and m.W>512 and math.abs(m.H-683)<1e-9 and m.rows[1].label=="Файлы" and m:title()=="Настройки")
m:openTab(1); assert(m.rows[5].sub=="Папки сортируются вместе с книгами")
p4:onCloseWidget()
G_reader_settings.data={language="en"}; screen.w=1072; screen.h=1448
print("PASS: landscape scale, Russian titles and hints")
