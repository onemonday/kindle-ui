-- Kindle-style top menu: hooks, sections from layout.lua, TouchMenu-compatible callbacks, scrolling.
local SM=require("settingsmenu")
local Items=require("menuitems")
local Base=require("ui/widget/container/widgetcontainer")
package.preload["ui/widget/infomessage"]=function() return Base end
G_reader_settings.data={language="en"}; screen.w=1072; screen.h=1448; device.touch=true
device.wifi=true; network.on=true

-- display-only capitalization
local U=Items.ucfirst
assert(U("name")=="Name" and U("Name")=="Name" and U("")=="" and U("123 pages")=="123 pages")
assert(U("привет")=="Привет" and U("ёлка")=="Ёлка" and U("Привет")=="Привет")
assert(U("eReader")=="eReader" and U("iOS")=="iOS" and U("éclair")=="Éclair")
assert(U("x")=="X")
local l,v=Items.splitLabel("Sort by: name"); assert(l=="Sort by" and v=="name")
l,v=Items.splitLabel("Plain"); assert(l=="Plain" and v==nil)
l,v=Items.splitLabel("Time: 12:30"); assert(l=="Time" and v=="12:30")
print("PASS: ucfirst Latin/Cyrillic/eReader/iOS, Label: value split")

-- Fake KOReader file manager menu: menu_items sorted by the MenuSorter double.
state, calls = nil, nil
FM_ORDER = {
 ["KOMenu:menu_buttons"]={"filemanager_settings","setting","tools","search","reader","main"},
 filemanager_settings={"filemanager_display_mode","filebrowser_settings","----------------------------","sort_by","reverse_sorting","sort_mixed","----------------------------","start_with"},
 setting={"frontlight","night_mode","----------------------------","network","screen","navigation","device","language"},
 network={"network_wifi","network_info","----------------------------","ssh"},
 screen={"screensaver","screen_dpi","screen_eink_opt"},
 navigation={"back_to_exit","back_in_filemanager"},
 device={"time","autosuspend"},
 tools={"calibre","profiles","----------------------------","more_tools"},
 more_tools={"synchronize_time","plugin_management"},
 search={"opds"},
 reader={},
 main={"history","help","exit_menu"},
 help={"search_menu","version"},
 exit_menu={"restart_koreader","exit"},
}
function radio(text,n) return {text=text,radio=true,checked_func=function() return state.radio==n end,callback=function() state.radio=n end} end
function fmMenuItems(menu)
 local items={["KOMenu:menu_buttons"]={},
  filemanager_settings={icon="appbar.filebrowser"}, setting={icon="appbar.settings"}, tools={icon="appbar.tools"},
  search={icon="appbar.search"}, main={icon="appbar.menu"},
  reader={icon="book.opened",remember=false,callback=function() calls.reader=true; menu:onCloseFileManagerMenu() end},
 }
 items.filemanager_display_mode={text="Display mode",sub_item_table={radio("classic (filename only)",1),radio("mosaic with cover images",2),
  {text="Use this mode everywhere",checked_func=function() return false end,callback=function() end}}}
 items.filebrowser_settings={text="Settings",sub_item_table={
  {text="Show hidden files",checked_func=function() return false end,callback=function() end},
  {text="History settings",sub_item_table={{text="Shorten date/time",checked_func=function() return false end,callback=function() end}}},
  {text="Home folder settings",sub_item_table={{text="Set home folder",callback=function() end}}}}}
 items.sort_by={text_func=function() return "Sort by: "..state.sort end,sub_item_table={radio("name",1),radio("date",2)}}
 items.reverse_sorting={text="Reverse sorting",checked_func=function() return state.reverse end,callback=function(tm) calls.reverse_tm=tm; state.reverse=not state.reverse end}
 items.sort_mixed={text="Folders and files mixed",checked_func=function() return false end,callback=function() end}
 items.start_with={text="Start with: file browser",sub_item_table={radio("file browser",1)}}
 items.frontlight={text="Frontlight",callback=function() end}
 items.night_mode={text="Night mode",checked_func=function() return false end,callback=function() end}
 items.network={text="Network"}; items.screen={text="Screen"}; items.navigation={text="Navigation"}; items.device={text="Device"}
 items.network_wifi={text="Wi-Fi connection",checked_func=function() return network.on end,callback=function() end}
 items.network_info={text="Network info",keep_menu_open=true,callback=function() end}
 items.ssh={text="SSH server",sub_item_table={{text="Start SSH server",callback=function() end}}}
 items.screensaver={text="Sleep screen",sub_item_table={{text="Wallpaper",sub_item_table={{text="x"}}}}}
 items.screen_dpi={text="Screen DPI",sub_item_table={radio("auto",1)}}
 items.screen_eink_opt={text="E-ink settings",sub_item_table={
  {text="Full refresh rate",sub_item_table={radio("Never",1)}},
  {text="Use smaller panning rate",checked_func=function() return false end,callback=function() end},
  {text_func=function() return "Sleep screen anti-ghosting redraws: off" end,keep_menu_open=true,callback=function() end}}}
 items.back_to_exit={text="Back to exit",sub_item_table={radio("ask",1)}}
 items.back_in_filemanager={text="Back in file browser",sub_item_table={radio("exit",1)}}
 items.time={text="Time and date",sub_item_table={{text="12-hour clock",checked_func=function() return false end,callback=function() end}}}
 items.autosuspend={text="Autosuspend timeout: 15 min",keep_menu_open=true,callback=function() end,sorting_hint="device"}
 items.language={text="Language",sub_item_table={radio("English",1)}}
 items.calibre={text="Calibre",sub_item_table={{text="Connect",callback=function() end}}}
 items.profiles={text="Profiles",sub_item_table={{text="New",callback=function() end}}}
 items.more_tools={text="More tools"}
 items.synchronize_time={text="Synchronize time",callback=function() end}
 items.plugin_management={text="Plugin management",sub_item_table={{text="x"}}}
 items.opds={text="OPDS catalog",callback=function() end}
 items.history={text="History",callback=function() end}
 items.help={text="Help"}
 items.search_menu={text="Menu search",keep_menu_open=true,callback=function() calls.search_event=true end}
 items.version={text="Version",keep_menu_open=true,callback=function() end}
 items.exit_menu={text="Exit"}
 items.restart_koreader={text="Restart KOReader",callback=function() end}
 items.exit={text="Exit",callback=function() end}
 -- Unknown plugins (no hint), sorted by key into Other plugins.
 items.t01_disabled={text="Disabled thing",enabled_func=function() return false end,callback=function() calls.disabled=true end,help_text="Help!"}
 items.t02_mandatory={text="Mandatory",mandatory_func=function() return "42" end,keep_menu_open=true,
  callback=function(tm) calls.keep=tm end,hold_callback=function(tm,item) calls.hold={tm,item} end}
 items.t03_replace={text="Replace items",keep_menu_open=true,callback=function(tm)
  tm.item_table={{text="fresh item"},{text="second"}}; tm.page=1; tm:updateItems() end}
 items.t04_close={text="Close me",callback=function(tm) calls.close_tm=tm end}
 items.t05_long={text="A very long label that certainly does not fit in one line of the Kindle menu, not even on the smaller design scale",sub_item_table_func=function()
  return {{text="up",keep_menu_open=true,callback=function(tm) tm:backToUpperMenu() end}} end}
 -- Switch and chevron on one row, like readerfont.lua font family items.
 items.t06_family={text="Font family",checked_func=function() return true end,
  checkmark_callback=function() calls.checkmark=(calls.checkmark or 0)+1 end,sub_item_table={{text="family font"}}}
 items.t07_wireless={text="Wireless",enabled_func=function() return state.connected end,keep_menu_open=true,
  callback=function() calls.wireless=(calls.wireless or 0)+1 end}
 items.t08_device={text_func=function() return "Device: "..string.rep("very long value ",8) end,keep_menu_open=true,callback=function() end}
 menu.plugin:addToMainMenu(items)
 return items
end
function newMenuUI(document)
 local ui=newUI(); ui.document=document
 local menu=ui.menu
 function menu:onPressMenu() self.original_calls=self.original_calls+1 end
 function menu:onRebuildMenu() self.rebuilds=(self.rebuilds or 0)+1; self.tab_item_table=nil end
 function menu:onMenuSearch() self.stock_search=true end
 function menu:onCloseFileManagerMenu()
  if not self.menu_container then return true end
  self.saved_tab=self.menu_container[1].last_index
  manager:close(self.menu_container); self.menu_container=nil; return true
 end
 function menu:setUpdateItemTable()
  self.menu_items=fmMenuItems(self)
  self.tab_item_table=require("ui/menusorter"):mergeAndSort("filemanager",self.menu_items,FM_ORDER)
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

-- root page: the ten sections with icon and subtitle
menu:onShowMenu(); local m=p.settings_menu
assert(m and manager.shown==m and menu.menu_container==m and menu.original_calls==4)
assert(manager.last_show.refresh=="flashui")
local labels={"Wi-Fi & network","Screen & light","Power & battery","Gestures & buttons","Language & dictionaries",
 "Library","Reading","Apps & plugins","Device","Help"}
local icons={"network","screen","power","gestures","language","library","reading","apps","device","help"}
assert(m.at_root and #m.rows==10, #m.rows)
for i,row in ipairs(m.rows) do
 assert(row.kind=="tab" and row.key==icons[i] and row.label==labels[i] and row.icon=="section-"..icons[i] and row.h==68 and row.sub and row.chevron, row.label)
end
assert(m:title()=="Settings" and m.max>0)
painted={}; m:paintTo(bb)
local function find(kind,pred) for _,v in ipairs(painted) do if v.kind==kind and pred(v) then return v end end end
assert(find("text",function(v) return v.text=="Wi-Fi & network" end))
assert(find("text",function(v) return v.text=="Wi-Fi, proxy, file transfer" and v.color==SM.colors.sub end))
assert(find("image",function(v) return v.file:find("section%-network%.svg") end))
assert(not find("image",function(v) return v.file:find("menu%-back%.svg") end), "no back arrow on root")
assert(find("image",function(v) return v.file:find("menu%-wifi%.svg") end))
print("PASS: hooks, setting off / non-touch / do_not_show keep stock menu, root shows the ten sections with icons and subtitles")

local function rowOf(label)
 for i,row in ipairs(m.rows) do if row.label==label then return i,row end end
 error("no row "..tostring(label))
end
local function tapAt(index,ux)
 local row=m.rows[index]
 return m:onKMenu_tap(nil,{pos={x=(ux or 200)*m.scale,y=(79+row.y-m.offset+row.h/2)*m.scale}})
end
local function holdAt(index)
 local row=m.rows[index]
 return m:onKMenu_hold(nil,{pos={x=100*m.scale,y=(79+row.y-m.offset+20)*m.scale}})
end
local function tapLabel(label,ux) local i=rowOf(label); local row=m.rows[i]
 if 79+row.y-m.offset+row.h>m.H or row.y<m.offset then m:scrollTo(row.y) end
 return tapAt(i,ux) end

-- Library: captions, KOReader rows, our View container
tapAt(6); assert(not m.at_root and m.cur_tab=="library" and m:title()=="Library")
local r=m.rows
assert(r[1].kind=="caption" and r[1].label=="OPEN" and r[1].h==34, "first caption")
local _,cont=rowOf("Continue reading"); assert(cont.item.callback and not cont.chevron)
local vi,view=rowOf("View"); assert(view.chevron and view.value=="Mosaic with cover images", "View shows the selected display mode")
local _,sort=rowOf("Sort by"); assert(sort.value=="Name" and sort.chevron, "Label: value split")
local _,rev=rowOf("Reverse sorting"); assert(rev.switch==false and rev.value==nil and not rev.chevron, "checkbox is a switch")
local _,mixed=rowOf("Folders and files mixed"); assert(mixed.sub=="Folders are sorted together with books" and mixed.h==68, "hint by MenuSorter id")
local _,start=rowOf("Start with"); assert(start.value=="File browser" and start.sub)
local _,home=rowOf("Home folder settings"); local _,hist=rowOf("History settings")
local _,fbs=rowOf("Settings"); assert(#fbs.item.sub_item_table==1, "home/history moved out of Settings")
for _,row in ipairs(m.rows) do assert(row.kind~="sep", "no KOReader separators on section pages") end
local caps={}; for _,row in ipairs(m.rows) do if row.kind=="caption" then caps[#caps+1]=row.label end end
assert(table.concat(caps,"|")=="OPEN|VIEW AND SORTING|STARTUP AND FOLDERS", table.concat(caps,"|"))
painted={}; m:paintTo(bb)
assert(find("text",function(v) return v.text=="VIEW AND SORTING" and v.bold and v.color==SM.colors.sub end), "caption is uppercase")
assert(find("rect",function(v) return v.color==SM.colors.group end), "rule above a caption")
assert(find("image",function(v) return v.file:find("menu%-back%.svg") end))
assert(find("image",function(v) return v.file:find("switch%-off%.svg") end))
-- checkbox: callback gets the menu, view refreshes, menu stays open
tapLabel("Reverse sorting"); assert(calls.reverse_tm==m and state.reverse and m.rows[rowOf("Reverse sorting")].switch==true and p.settings_menu==m)
-- View > Library view > radio
tapLabel("View"); assert(m:title()=="View" and m.rows[1].label=="Library view" and m.rows[1].value=="Mosaic with cover images")
tapAt(1); assert(m:title()=="Library view" and m.rows[1].kind=="radio" and #m.item_table_stack==2)
assert(m.rows[1].label=="Classic (filename only)" and not m.rows[1].on and m.rows[2].on)
painted={}; m:paintTo(bb)
assert(find("image",function(v) return v.file:find("menu%-radio%-on%.svg") end))
assert(find("text",function(v) return v.text=="Mosaic with cover images" and v.bold end))
tapAt(1); assert(state.radio==1 and m.rows[1].on and p.settings_menu==m, "radio stays open and refreshes")
m:onKMenu_tap(nil,{pos={x=20*m.scale,y=54*m.scale}}); assert(m:title()=="View")
m:onBack(); assert(m:title()=="Library" and m.rows[rowOf("View")].value=="Classic (filename only)")
m:onBack(); assert(m.at_root)

-- Apps: unknown plugins in Other plugins, item semantics
m:openTab("apps"); assert(m:title()=="Apps & plugins")
local oi=rowOf("OTHER PLUGINS"); assert(m.rows[oi].kind=="caption")
local _,dis=rowOf("Disabled thing"); assert(dis.enabled==false)
painted={}; m:scrollTo(m.rows[rowOf("Disabled thing")].y); m:paintTo(bb)
local dtext=find("text",function(v) return v.text=="Disabled thing" end)
assert(dtext.color==SM.colors.disabled and not dtext.bold, "disabled label is grey")
for _,row in ipairs(m.rows) do assert(not (row.label or ""):find("NEW:"), "NEW: prefix stripped") end
-- disabled rows are not tappable; hold shows help
tapLabel("Disabled thing"); assert(not calls.disabled and p.settings_menu==m)
manager.shown=nil; holdAt(rowOf("Disabled thing")); assert(manager.shown and manager.shown.text=="Help!"); manager.shown=m
-- keep_menu_open, mandatory value and hold_callback
local _,mand=rowOf("Mandatory"); assert(mand.value=="42", "mandatory_func is the value")
tapLabel("Mandatory"); assert(calls.keep==m and p.settings_menu==m)
holdAt(rowOf("Mandatory")); assert(calls.hold[1]==m and calls.hold[2]==mand.item)
-- sub_item_table_func and backToUpperMenu from a callback
local li,long=rowOf(m.rows[rowOf("Mandatory")+3].label); assert(long.chevron and long.label:sub(1,6)=="A very")
m:scrollTo(long.y); painted={}; m:paintTo(bb); assert(long.truncated, "long label is truncated")
manager.shown=nil; holdAt(li); assert(manager.shown and manager.shown.text==long.item.text, "hold on a truncated label shows the full text"); manager.shown=m
tapAt(li); assert(#m.item_table_stack==1 and m.rows[1].label=="Up")
tapAt(1); assert(#m.item_table_stack==0 and m:title()=="Apps & plugins")
-- a callback replacing item_table and page
tapLabel("Replace items"); assert(#m.rows==2 and m.rows[1].label=="Fresh item" and p.settings_menu==m)
m:backToUpperMenu(); assert(m.at_root)
-- switch vs chevron, live enabled_func, truncated value
m:openTab("apps"); reset(); state.connected=true
local fi,fam=rowOf("Font family"); assert(fam.switch==true and fam.chevron)
m:scrollTo(fam.y); local right=m.W-(m.max>0 and 58 or 32)
tapAt(fi,right-4.5); assert(not calls.checkmark and m:title()=="Font family", "chevron opens the submenu")
m:onBack(); m:scrollTo(m.rows[fi].y)
tapAt(fi,right-23-25); assert(calls.checkmark==1 and m:title()=="Apps & plugins", "switch runs checkmark_callback")
local wi=rowOf("Wireless"); m:scrollTo(m.rows[wi].y)
state.connected=false; tapAt(wi,100); assert(not calls.wireless, "enabled_func is evaluated at tap time")
state.connected=true; m.rows[wi].enabled=false; tapAt(wi,100); assert(calls.wireless==1, "stale disabled cache does not block")
local di,dev=rowOf("Device"); assert(dev.value); m:scrollTo(dev.y)
painted={}; m:paintTo(bb); assert(dev.truncated, "a cut value marks the row truncated")
manager.shown=nil; holdAt(di); assert(manager.shown and manager.shown.text==dev.item.text_func(), "hold shows the whole row text"); manager.shown=m
-- an ordinary action closes the menu (no keep_menu_open)
tapLabel("Close me"); assert(calls.close_tm==m and not p.settings_menu and m.closed and menu.menu_container==nil)
assert(menu.saved_tab==1, "KOReader saves last tab through menu_container[1]")
print("PASS: captions, View container, switch/radio/value/mandatory/hint/disabled mapping, Other plugins, touchmenu_instance callbacks, keep_menu_open")

-- action row, onShowMenu(tab) maps to sections, remember=false
menu:onShowMenu(); m=p.settings_menu; m:openTab("library"); tapLabel("Continue reading"); assert(calls.reader and not p.settings_menu)
menu:onShowMenu(1); m=p.settings_menu; assert(m:title()=="Library", "Files tab opens Library")
m:backToUpperMenu(); assert(m.at_root and p.settings_menu==m)
m:backToUpperMenu(); assert(not p.settings_menu, "Back on root closes")
menu:onShowMenu(3); m=p.settings_menu; assert(m:title()=="Apps & plugins", "Tools tab opens Apps"); m:closeMenu()
calls.reader=nil
menu:onShowMenu(5); m=p.settings_menu; assert(m.at_root and not calls.reader, "remember=false tab is not auto-run")
m:closeMenu()

-- openMenuItem routes into the new tree
p:openMenuItem("sort_mixed"); m=p.settings_menu
assert(m and m:title()=="Library" and m.rows[rowOf("Folders and files mixed")])
p:openMenuItem("kindle_drawer"); assert(p.settings_menu==m and m:title()=="Kindle Drawer" and #m.item_table_stack==1)
assert(m.rows[1].label=="Kindle-style menu" and m.rows[1].sub=="Replaces the KOReader top menu" and m.rows[2].kind=="sep")
m:onBack(); assert(m:title()=="Apps & plugins"); m:onBack(); assert(m.at_root)
p:openMenuItem("ssh"); assert(m:title()=="SSH server", "drawer long-press shortcut lands in the SSH submenu")
p:openMenuItem("back_button"); assert(m:title()=="Back button" and m.rows[1].label=="Back to exit")
m:closeMenu()

-- ⋮ popup actions (no book: two entries)
menu:onShowMenu(2); m=p.settings_menu
m:onKMenu_tap(nil,{pos={x=(m.W-66)*m.scale,y=54*m.scale}}); assert(m.popup and #m:popupItems()==2)
painted={}; m:paintTo(bb); assert(find("text",function(v) return v.text=="Classic KOReader menu" end))
assert(not find("text",function(v) return v.text=="Book actions" end))
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
print("PASS: action row, onShowMenu(tab) → section, remember=false, openMenuItem routing, ⋮ classic/plugin actions")

-- Menu search: KOReader's item sends ShowMenuSearch; menu_container[1] has the method too
local Dialog=Base:extend{}
function Dialog:getInputText() return self.typed end
package.loaded["ui/widget/inputdialog"]=Dialog
menu:onShowMenu(); m=p.settings_menu
assert(menu.menu_container[1].onShowMenuSearch, "menu_container[1] answers onShowMenuSearch")
menu.menu_container[1]:onShowMenuSearch(); local dlg=manager.shown; assert(dlg.title=="Search menu entry")
dlg.typed="SSH"; dlg.buttons[1][2].callback()
assert(G_reader_settings.data.menu_search_string=="ssh" and m:title()=="Search results", tostring(G_reader_settings.data.menu_search_string).." "..tostring(m:title()).." "..tostring(m.closed))
local found=m.rows[1]; assert(found.label=="SSH server" and found.sub=="Wi-Fi & network", found.sub)
tapAt(1); assert(m:title()=="SSH server" and #m.item_table_stack==1, "result opens the found item")
m:onBack(); assert(m:title()=="Wi-Fi & network")
m:showSearchResults("full refresh"); assert(m.rows[1].label=="Full refresh rate" and m.rows[1].sub=="Reading")
m:showSearchResults("zzzz"); assert(manager.shown.text=="No menus containing 'zzzz' found.")
manager.shown=m; m:closeMenu()
-- Dispatcher's Menu search opens our menu with the search dialog
menu:onMenuSearch(); assert(p.settings_menu and manager.shown.title=="Search menu entry" and not menu.stock_search); p:closeSettingsMenu()
print("PASS: menu search over the new tree, results open the item, menu_container[1]:onShowMenuSearch")

-- scrolling: snapping, clamping, last row on the bottom edge, fling, throttled fast refresh
local long_list={}
for i=1,30 do long_list[i]={text="option "..i,keep_menu_open=true,callback=function() end} end
long_list[5].separator=true
local function openLong() menu:onShowMenu(); m=p.settings_menu; m:openTab("help"); m:pushPage({text="Long"},long_list) end
openLong()
assert(#m.rows==31 and m.max>0 and m.total==30*56+11)
local last=m.rows[#m.rows]
m:scrollTo(1e9); assert(m.offset==m.max and math.abs(last.y+last.h-m.offset-m.view_h)<1e-6, "last row on the bottom edge")
m:scrollTo(-50); assert(m.offset==0)
m:scrollTo(80); assert(m.offset==56)
m:scrollTo(56*5+11+10); assert(m.offset==56*5+11, "snaps to a row top after a separator")
for _,s in ipairs(m.snaps) do assert(s>=0 and s<=m.max) end
painted={}; m:paintTo(bb)
assert(find("image",function(v) return v.file:find("menu%-down%.svg") end) and find("image",function(v) return v.file:find("menu%-up%.svg") end))
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
m:onKMenu_pan_release(nil,{pos={x=x,y=y0-130*m.scale},time=1300*1000})
assert(m.offset==112 and manager.last_dirty.refresh=="ui" and not manager.scheduled)
clock_ms=2000
m:onKMenu_pan(nil,{start_pos={x=x,y=y0},pos={x=x,y=y0-20*m.scale},relative={x=0,y=-20*m.scale},time=2000*1000})
m:onKMenu_pan(nil,{start_pos={x=x,y=y0},pos={x=x,y=y0-60*m.scale},relative={x=0,y=-60*m.scale},time=2040*1000})
m:onKMenu_swipe(nil,{direction="north",pos={x=x,y=y0},end_pos={x=x,y=y0-60*m.scale},time=2050*1000})
assert(m.offset==m:nearestSnap(492) and m.offset>400, "fling adds momentum")
local before_flick=m.offset
m:onKMenu_swipe(nil,{direction="north",pos={x=x,y=y0},end_pos={x=x,y=y0-50*m.scale},distance=50*m.scale,time=2600*1000})
assert(m.offset>before_flick+50 and m.offset==m:nearestSnap(m.offset))
m:scrollTo(0)
-- swipe east goes back, like the ← button
m:onKMenu_swipe(nil,{direction="east",pos={x=x,y=y0},end_pos={x=x+300,y=y0}}); assert(m:title()=="Help" and p.settings_menu==m)
m:pushPage({text="Long"},long_list)
m:onKMenu_pan(nil,{start_pos={x=x,y=y0},pos={x=x,y=y0-5000*m.scale},relative={x=0,y=-5000*m.scale},time=3000*1000})
m:onKMenu_pan_release(nil,{pos={x=x,y=y0-5000*m.scale},time=3500*1000})
assert(m.offset==m.max)
m:scrollTo(0)
local bar=m:scrollbar()
m:onKMenu_tap(nil,{pos={x=(m.W-21)*m.scale,y=(bar.bottom-9)*m.scale}})
assert(m.offset==m:nearestSnap(m.view_h-56) and m.offset>0)
m:onPrevPage(); assert(m.offset==0)
m:onNextPage(); local page2=m.offset; assert(page2>0 and m.page==2)
m:updateItems(); assert(m.offset==page2)
m.page=1; m:updateItems(); assert(m.offset==0)
m:onKMenu_pan(nil,{start_pos={x=x,y=40*m.scale},pos={x=x,y=300*m.scale},relative={x=0,y=260*m.scale}})
assert(m.offset==0); m:onKMenu_pan_release(nil,{pos={x=x,y=300*m.scale}})
-- multiswipe settles a drag, mouse wheel scrolls three rows
m:onKMenu_pan(nil,{start_pos={x=x,y=y0},pos={x=x,y=y0-130*m.scale},relative={x=0,y=-130*m.scale},time=5000*1000})
m:onKMenu_multiswipe(nil,{pos={x=x,y=y0},end_pos={x=x+200,y=y0-130*m.scale},time=5400*1000})
assert(m.offset==112 and not m.drag and manager.last_dirty.refresh=="ui", "multiswipe settles the drag")
m:onPan(nil,{mousewheel_direction=-1,direction="north"}); assert(m.offset==291)
local after=m.offset; m:onPan(nil,{mousewheel_direction=1,direction="south"}); assert(m.offset<after)
m:closeMenu()
print("PASS: continuous scroll, snap to row tops, clamp, last row on bottom edge, fling, 80 ms fast refresh, ▲▼/page keys, multiswipe, wheel")

-- mutual exclusion, suspend, dimension change, rebuild, teardown
menu:onShowMenu(); m=p.settings_menu
m:onKMenu_tap(nil,{pos={x=m.W/2*m.scale,y=12*m.scale}}); assert(p.drawer and not p.settings_menu, "chevron opens the top drawer")
p:activate("settings"); assert(p.settings_menu and not p.drawer, "All Settings opens the new menu")
m=p.settings_menu; m:onKMenu_swipe(nil,{direction="south",pos={x=500,y=20},end_pos={x=500,y=400}})
assert(p.drawer and not p.settings_menu, "swipe down from the status bar opens the top drawer")
p:activate("settings")
p:onSuspend(); assert(not p.settings_menu)
menu:onShowMenu(); m=p.settings_menu; p:onSetDimensions(); assert(p.settings_menu==m and not m.closed)
p:onKindleDrawer(); p:onSetDimensions(); assert(not p.drawer and not p.settings_menu)
menu:onShowMenu(1); m=p.settings_menu; tapLabel("View")
menu:onRebuildMenu(); assert(menu.rebuilds==1)
local m2=p.settings_menu; assert(m2 and m2~=m and m.closed and m2:title()=="View" and m2.cur_tab=="library", "rebuild restores the section and page")
assert(m2.rows[1].label=="Library view")
p:onCloseWidget(); assert(not p.settings_menu and m2.closed)
for name,fn in pairs(originals) do assert(menu[name]==fn, name.." restored") end
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
assert(math.abs(m.scale-1072/683)<1e-9 and m.W>512 and math.abs(m.H-683)<1e-9 and m.rows[1].label=="Wi-Fi и сеть" and m:title()=="Настройки")
assert(m.rows[8].label=="Приложения и плагины" and m.rows[8].sub=="Инструменты, сервисы, управление плагинами")
m:openTab("library"); m=p4.settings_menu
local found_ru=false; for _,row in ipairs(m.rows) do if row.sub=="Папки сортируются вместе с книгами" then found_ru=true end end
assert(found_ru and m.rows[1].label=="ОТКРЫТЬ")
p4:onCloseWidget()
G_reader_settings.data={language="en"}; screen.w=1072; screen.h=1448
print("PASS: landscape scale, Russian sections, captions and hints")
