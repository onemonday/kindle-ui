-- New menu layout on fake KOReader menus: every item placed once or reported,
-- unknown plugins, the safety net, classic tree untouched, book actions, drawer tabs.
local Layout=require("layout")
local Items=require("menuitems")
local MenuSorter=require("ui/menusorter")
G_reader_settings.data={language="en"}; screen.w=1072; screen.h=1448; device.touch=true; device.wifi=true
state={radio=1,sort="name",reverse=false}; calls={}

-- Snapshot of a tree's shape: every table's children by identity and text.
local function capture(tree)
 local seen, out = {}, {}
 local function walk(list, depth)
  if depth>12 or seen[list] then return end
  seen[list]=true
  local entry={list=list}
  for i,item in ipairs(list) do
   if type(item)=="table" then
    entry[i]={item=item,text=item.text,sub=item.sub_item_table,id=item.id}
    if type(item.sub_item_table)=="table" then walk(item.sub_item_table,depth+1) end
   end
  end
  out[#out+1]=entry
 end
 for _,tab in ipairs(tree) do walk(tab,1) end
 return out
end
local function same(a,b)
 if #a~=#b then return false, "table count" end
 for i,ea in ipairs(a) do
  local eb=b[i]
  if ea.list~=eb.list or #ea.list~=#eb.list then return false, "list "..i end
  for j,ca in pairs(ea) do
   if j~="list" then local cb=eb[j]
    if ca.item~=cb.item or ca.text~=cb.text or ca.sub~=cb.sub or ca.id~=cb.id then return false, "child "..i.."/"..j end
   end
  end
 end
 return true
end
-- Count where each snapshot key shows up in what we built (sections, book, drawer rows).
local function placements(layout, snap)
 local by_item={}
 for key,item in pairs(snap.items) do by_item[item]=key end
 local counts, seen = {}, {}
 local function count(key) if key then counts[key]=(counts[key] or 0)+1 end end
 local function walk(list, depth)
  if depth>12 then return end
  for _,item in ipairs(list) do
   if type(item)=="table" and not seen[item] then
    seen[item]=true
    count(item.kd_view_of or by_item[item])
    if type(item.sub_item_table)=="table" then walk(item.sub_item_table,depth+1) end
   end
  end
 end
 for _,s in ipairs(layout.sections) do walk(s,1) end
 if layout.book then walk(layout.book,1) end
 for _,tab in ipairs(layout.drawer_tabs or {}) do for _,seg in ipairs(tab) do if seg.item then walk({seg.item},1) end end end
 return counts
end
local function section(layout,key) for _,s in ipairs(layout.sections) do if s.kd_key==key then return s end end end
local function labels(list) local t={} for _,item in ipairs(list) do t[#t+1]=item.kd_caption and ("#"..item.kd_caption) or Items.text(item) end return t end
local function contains(list,text) for _,item in ipairs(list) do if not item.kd_caption and Items.text(item)==text then return item end end end

-- File manager: the fake menu from menu.lua plus unknown plugins.
local fakeMenu={plugin=Plugin:new{ui=newUI()}}
local function fmItems()
 local items=fmMenuItems(fakeMenu)
 items.zz_nohint={text="No hint plugin",callback=function() end}
 items.zz_bogus={text="Bogus hint plugin",sorting_hint="no_such_menu",callback=function() end}
 items.zz_textfunc={text_func=function() return "Text func plugin" end,callback=function() end}
 items.zz_network={text="Network plugin",sorting_hint="network",callback=function() end}
 items.zz_inside={text="Inside sleep screen",sorting_hint="screensaver",callback=function() end}
 items.zz_leafhint={text="Leaf hint plugin",sorting_hint="network_info",callback=function() end}
 items.zz_off={text="Disabled by user",callback=function() end}
 -- A hint on a submenu in Apps & plugins that MenuSorter cannot fill (sub_item_table_func).
 items.profiles={text="Profiles",sub_item_table_func=function() return {{text="New"}} end}
 items.zz_apphint={text="Apps hint plugin",sorting_hint="profiles",callback=function() end}
 return items
end
local order={}; for k,v in pairs(FM_ORDER) do order[k]=v end
order["KOMenu:disabled"]={"zz_off"}
-- Without the guard the bogus hint crashes MenuSorter, as in KOReader.
local Raw=dofile("tests/menusorter_fake.lua")
assert(not pcall(Raw.sort, Raw, fmItems(), order), "the double reproduces the crash")
assert(Layout.installSortGuard())
log_lines={}
local items=fmItems()
local tree=MenuSorter:mergeAndSort("filemanager", items, order)
local snap=Layout.snapshotFor(tree)
assert(snap and snap.items.zz_textfunc and snap.items.zz_bogus and snap.bad_hints.no_such_menu)
local warned=false; for _,line in ipairs(log_lines) do if line:find("zz_bogus",1,true) and line:find("^warn") then warned=true end end
assert(warned, "unknown sorting_hint is logged")
local classic_more; for _,tab in ipairs(tree) do for _,it in ipairs(tab) do if it.id=="more_tools" then classic_more=it.sub_item_table end end end
assert(contains(classic_more,"Bogus hint plugin"), "classic: unknown hint falls back to More tools")
local before=capture(tree)
local layout=Layout.build{tree=tree,snapshot=snap,reader=false,kind="rolling",drawer=true,show_networks=function() calls.networks=true end,report=true}
local ok,why=same(before,capture(tree)); assert(ok, "classic tree unchanged: "..tostring(why))
assert(#layout.sections==10 and not layout.book and not layout.drawer_tabs)

-- every snapshot key placed exactly once, or reported
local counts=placements(layout,snap)
local reported={}
for _,k in ipairs(layout.report.dissolved) do reported[k]="dissolved" end
for _,k in ipairs(layout.report.disabled) do reported[k]="disabled" end
for key in pairs(snap.items) do
 if reported[key] then assert(not counts[key], key.." is "..reported[key].." but shown")
 else assert(counts[key]==1, key.." placed "..tostring(counts[key]).." times") end
end
assert(reported.zz_off=="disabled" and reported.network=="dissolved" and reported.setting=="dissolved" and reported.exit_menu=="dissolved")
-- unknown plugins: Other plugins, no NEW:, no crash; hints follow the moved container
local apps=section(layout,"apps")
local other=labels(apps); local joined=table.concat(other,"|")
assert(joined:find("#Other plugins|Disabled thing",1,true) and joined:find("|Bogus hint plugin|Leaf hint plugin|No hint plugin|Text func plugin|#Management",1,true), joined)
assert(not joined:find("NEW:",1,true), "NEW: prefix stripped")
assert(snap.items.zz_nohint.text=="NEW: No hint plugin", "classic keeps KOReader's NEW: prefix")
local net=section(layout,"network"); assert(Items.text(net[#net])=="Network plugin" and layout.report.routed.zz_network=="network")
assert(layout.report.routed.zz_leafhint=="other", "hint on an item without submenu goes to Other plugins")
assert(layout.report.routed.zz_apphint=="other" and contains(apps,"Apps hint plugin"), "a hint into Apps & plugins lands in Other plugins, not nowhere")
local sleep=contains(section(layout,"screen"),"Sleep screen"); assert(contains(sleep.sub_item_table,"Inside sleep screen"), "hint into a kept submenu stays there")
assert(#layout.report.net==0, "no known key fell to the safety net")
-- extracted children: views, classic stays whole
local eink=contains(section(layout,"screen"),"E-ink settings"); assert(eink.kd_view_of=="screen_eink_opt" and #eink.sub_item_table==1)
assert(#snap.items.screen_eink_opt.sub_item_table==3)
assert(Items.text(sleep.sub_item_table[#sleep.sub_item_table])=="Sleep screen anti-ghosting redraws: off", "anti-ghosting joins Sleep screen")
assert(Items.text(section(layout,"reading")[1])=="Full refresh rate")
local dt=contains(section(layout,"device"),"Date and time"); assert(dt.kd_view_of=="time" and Items.text(dt.sub_item_table[#dt.sub_item_table])=="Synchronize time")
assert(#snap.items.time.sub_item_table==1, "classic Time and date unchanged")
local wifi=section(layout,"network"); assert(Items.text(wifi[2])=="Wi-Fi networks"); wifi[2].callback(); assert(calls.networks)
-- captions without rows are gone
for _,s in ipairs(layout.sections) do
 for i,item in ipairs(s) do if item.kd_caption then assert(s[i+1] and not s[i+1].kd_caption, "empty caption "..item.kd_caption) end end
end
assert(not contains(section(layout,"power"),"x") and labels(section(layout,"power"))[1]=="Autosuspend timeout: 15 min")
print("PASS: FM layout places every key once or reports it; unknown/bogus/text_func plugins in Other plugins without NEW:; classic tree unchanged")

-- Reader: book actions, drawer rows, net
local R_ORDER={
 ["KOMenu:menu_buttons"]={"navi","typeset","setting","tools","search","filemanager","main"},
 navi={"table_of_contents","bookmarks","go_to","navi_settings","autoturn"},
 navi_settings={"toc_items_per_page","----------------------------","page_map","bookmarks_settings"},
 typeset={"document_settings","change_font","typography","highlight_options","selection_text"},
 setting={"network","screen","taps_and_gestures","status_bar"},
 network={"network_wifi"}, screen={"screensaver"}, taps_and_gestures={"page_turns","follow_links"},
 tools={"progress_sync","more_tools"}, more_tools={"plugin_management"},
 search={"fulltext_search"}, filemanager={}, main={"book_status","book_info","history"},
}
face_calls=0
local function readerItems(paging)
 local face_table={{text="Font settings",sub_item_table={{text="Fallback fonts"}}},
  {text_func=function() return "Font-family fonts (2)" end,sub_item_table_func=function() return {{text="serif"}} end},
  {text="Literata",radio=true,checked_func=function() return true end,callback=function() end}}
 local t={["KOMenu:menu_buttons"]={},navi={icon="appbar.navigation"},typeset={icon="appbar.typeset"},setting={icon="appbar.settings"},
  tools={icon="appbar.tools"},search={icon="appbar.search"},main={icon="appbar.menu"},
  filemanager={icon="appbar.filebrowser",remember=false,callback=function() calls.fm=true end},
  table_of_contents={text="Table of contents",callback=function() end}, bookmarks={text="Bookmarks",callback=function() end},
  go_to={text="Go to page",callback=function() end},
  navi_settings={text="Settings"}, toc_items_per_page={text="ToC entries per page",callback=function() end},
  page_map={text="Stable page numbers",sub_item_table={{text="x"}}}, bookmarks_settings={text="Bookmarks",sub_item_table={{text="y"}}},
  autoturn={text="Autoturn",checked_func=function() return false end,callback=function() end,sorting_hint="navi"},
  document_settings={text="Document settings",sub_item_table={{text="Reset"}}},
  change_font={text_func=function() return "Font: Literata" end,sub_item_table_func=function() face_calls=face_calls+1; return face_table end},
  typography={text="Typography rules",sub_item_table={{text="z"}}},
  highlight_options={text="Highlights",sub_item_table={{text="h"}}},
  selection_text={text="Text selection tools",sub_item_table={{text="s"}}},
  typesetfootnotes={text="Footnotes and links",sorting_hint="selection_text",sub_item_table={{text="f"}}},
  network={text="Network"}, screen={text="Screen"}, taps_and_gestures={text="Taps and gestures"},
  network_wifi={text="Wi-Fi connection",checked_func=function() return true end,callback=function() end},
  screensaver={text="Sleep screen",sub_item_table={{text="Wallpaper",sub_item_table={{text="w"}}},
   {text="Do not show this book cover on sleep screen",checked_func=function() return false end,callback=function() end}}},
  page_turns={text="Page turns",sub_item_table={{text="Invert",checked_func=function() return false end,callback=function() end}}},
  follow_links={text="Links",sub_item_table={{text="l"}}},
  status_bar={text="Status bar",sub_item_table={{text="b"}}},
  progress_sync={text="Progress sync",sub_item_table={{text="Custom sync server",callback=function() end},
   {text="Push progress from this device now",callback=function() end},{text="Pull progress from other devices now",callback=function() end}}},
  more_tools={text="More tools"}, plugin_management={text="Plugin management",sub_item_table={{text="p"}}},
  fulltext_search={text="Fulltext search",callback=function() end},
  book_status={text="Book status",callback=function() end}, book_info={text="Book information",callback=function() end},
  history={text="History",callback=function() end},
 }
 if paging then t.change_font=nil; t.page_map=nil; t.typography=nil end
 return t, face_table
end
local ritems, face_table = readerItems(false)
local rtree=MenuSorter:mergeAndSort("reader", ritems, R_ORDER)
local rsnap=Layout.snapshotFor(rtree)
local rbefore=capture(rtree)
face_calls=0
local rl=Layout.build{tree=rtree,snapshot=rsnap,reader=true,kind="rolling",drawer=true,report=true}
assert(face_calls==0, "sub_item_table_func parents are not run at build time")
local function drawerRow(l,key) for _,tab in ipairs(l.drawer_tabs) do for _,seg in ipairs(tab) do if seg.row==key then return seg.item end end end end
ok,why=same(rbefore,capture(rtree)); assert(ok, "reader classic tree unchanged: "..tostring(why))
assert(#face_table==3 and #rsnap.items.screensaver.sub_item_table==2 and #rsnap.items.progress_sync.sub_item_table==3)
local rcounts=placements(rl,rsnap)
local rrep={}
for _,k in ipairs(rl.report.dissolved) do rrep[k]=true end
for key in pairs(rsnap.items) do
 if rrep[key] then assert(not rcounts[key], key) else assert(rcounts[key]==1, key.." placed "..tostring(rcounts[key])) end
end
assert(#rl.report.net==0)
-- book actions page
local book=rl.book; assert(book and book.text=="Book actions", table.concat(labels(rl.sections[#rl.sections]),"|"))
assert(table.concat(labels(book),"|")=="Table of contents|Bookmarks|Go to page|#Search|Fulltext search|#Book|Book status|Do not show this book cover on sleep screen|Push progress from this device now|Pull progress from other devices now|Book information", table.concat(labels(book),"|"))
local rsleep=contains(section(rl,"screen"),"Sleep screen"); assert(#rsleep.sub_item_table==1, "book cover option moved to book actions")
assert(#contains(section(rl,"reading"),"Progress sync").sub_item_table==3, "push/pull are copies")
-- drawer rows: KOReader items or views, not in the top menu
local d=setmetatable({},{__index=function(_,k) return drawerRow(rl,k) end})
assert(d.change_font.kd_view_of=="change_font" and #Items.subTable(d.change_font)==1, "Font list without its two settings rows")
assert(Items.text(d.font_settings)=="Font settings" and Items.text(d.font_family)=="Font-family fonts (2)")
assert(d.links==rsnap.items.follow_links and d.page_turns and d.status_bar and d.autoturn and d.document_settings)
assert(#d.navi_settings.sub_item_table==1 and d.page_map and d.bookmarks_settings, "page_map and bookmarks moved out of navi_settings")
assert(#d.selection_text.sub_item_table==2, "typesetfootnotes stays in selection_text while Links exists")
for _,s in ipairs(rl.sections) do for _,item in ipairs(s) do assert(item~=d.page_turns and Items.text(item)~="Typography rules") end end
-- drawer off: its rows join Reading under the tab names
local rl2=Layout.build{tree=rtree,snapshot=rsnap,reader=true,kind="rolling",drawer=false,report=true}
local reading=table.concat(labels(section(rl2,"reading")),"|")
assert(reading:find("#Font|Font|#Fonts",1,true)==nil and reading:find("#Font|Font|Font-family fonts (2)|Typography rules|Font settings|#Layout|Typography",1,true)==nil)
assert(reading:find("#Reading|Page turns|Links|Highlights|Text selection tools|Autoturn",1,true), reading)
-- paging document: rows of the rolling-only spec that exist fall to the net and are logged
local pitems=readerItems(true); pitems.change_font={text="Font: x",sub_item_table={{text="Font settings"}}}
local ptree=MenuSorter:mergeAndSort("reader", pitems, R_ORDER)
log_lines={}
local pl=Layout.build{tree=ptree,snapshot=Layout.snapshotFor(ptree),reader=true,kind="paging",drawer=true,report=true}
assert(#pl.report.net==1 and pl.report.net[1]=="change_font", table.concat(pl.report.net,","))
assert(contains(section(pl,"apps"),"Font: x"), "net item shown in Other plugins")
local logged=false; for _,line in ipairs(log_lines) do if line:find("change_font",1,true) and line:find("^warn") then logged=true end end
assert(logged, "net item logged")
assert(not drawerRow(pl,"change_font") and drawerRow(pl,"status_bar"))
print("PASS: reader layout, book actions page, drawer rows as views, drawer-off fallback, paging safety net with a log line")

-- The plugin opens book actions from the settings ⋮ and from Quick actions ⋮
local function readerUI()
 local ui=newUI(); ui.document={getPageCount=function() return 10 end}; ui.doc_props={display_title="Book"}
 function ui:getCurrentPage() return 1 end
 local menu=ui.menu
 function menu:onCloseReaderMenu() if self.menu_container then manager:close(self.menu_container); self.menu_container=nil end end
 function menu:setUpdateItemTable() self.tab_item_table=MenuSorter:mergeAndSort("reader", readerItems(false), R_ORDER) end
 return ui
end
local ui=readerUI(); local p=Plugin:new{ui=ui}
ui.menu:onShowMenu(); local m=p.settings_menu
assert(#m:popupItems()==3 and m:popupItems()[1].text=="Book actions")
m:onKMenu_tap(nil,{pos={x=(m.W-66)*m.scale,y=54*m.scale}}); m:onKMenu_tap(nil,{pos={x=(m.W-100)*m.scale,y=(70+20)*m.scale}})
assert(m:title()=="Book actions" and m.rows[1].label=="Table of contents" and not m.standalone)
m:onBack(); assert(m.at_root); m:closeMenu()
p.settings.kindle_menu=false -- the ⋮ in Quick actions works with the stock menu too
p:onQuickActionsPanel(); local q=p.quick_actions_panel
q:onQuick_tap(nil,{pos={x=652*q.scale,y=79*q.scale}})
m=p.settings_menu; assert(m and not p.quick_actions_panel and m:title()=="Book actions" and m.standalone)
m:onBack(); assert(m.closed and not p.settings_menu, "Back closes book actions opened from Quick actions")
p.settings.kindle_menu=nil
-- drawer long-press shortcut into progress sync, menu search finds book actions
p:openMenuItem("progress_sync"); m=p.settings_menu; assert(m:title()=="Progress sync")
local found=m:search("book status"); assert(found[1].key=="book")
m:closeMenu(); p:onCloseWidget()
print("PASS: book actions from settings ⋮ and Quick actions ⋮ (stock menu too), Back closes the standalone page, openMenuItem/search in a book")

-- Drawer tabs with fake ReaderConfig schemas
local Base=require("ui/widget/container/widgetcontainer")
local saved={}
for _,name in ipairs({"ui/widget/configdialog","ui/widget/iconwidget","ui/widget/textboxwidget","bottomdrawer"}) do saved[name]=package.loaded[name] or false end
local Config=Base:extend{}
function Config:findOptionByName(name)
 for _,panel in ipairs(self.config_options) do for _,o in ipairs(panel.options) do if o.name==name then return o end end end
end
function Config:onConfigChoose(values,name,event,args,index) self.configurable[name]=values[index] end
function Config:closeDialog() manager:close(self) end
package.loaded["ui/widget/configdialog"]=Config
package.loaded["ui/widget/iconwidget"]=Base
local TextBox=Base:extend{}
function TextBox:getAllLineCount() return 1 end
function TextBox:getVisLineCount() return 10 end
function TextBox:scrollToRatio() end
function TextBox:free() end
function TextBox:paintTo() end
package.loaded["ui/widget/textboxwidget"]=TextBox
package.loaded.bottomdrawer=nil; package.loaded.inlinepanels=nil
local function opt(name, extra) local o={name=name,name_text=name,values={1,2},args={1,2},toggle={"a","b"},default_value=1}
 for k,v in pairs(extra or {}) do o[k]=v end; return o end
local CRE={prefix="copt",
 {icon="appbar.rotation",options={opt("rotation_mode"),opt("visible_pages")}},
 {icon="appbar.crop",options={opt("h_page_margins")}},
 {icon="appbar.pageview",options={opt("view_mode"),opt("line_spacing")}},
 {icon="appbar.textsize",options={opt("font_size"),opt("font_fine_tune"),opt("word_spacing")}},
 {icon="appbar.contrast",options={opt("font_gamma"),opt("font_base_weight")}},
 {icon="appbar.settings",options={opt("status_line"),opt("embedded_css"),opt("embedded_fonts"),opt("smooth_scaling")}},
}
local KOPT={prefix="kopt",
 {icon="appbar.rotation",options={opt("rotation_mode")}},
 {icon="appbar.crop",options={opt("trim_page"),opt("page_margin")}},
 {icon="appbar.pagefit",options={opt("zoom_mode_type")}},
 {icon="appbar.pageview",options={opt("page_scroll"),opt("line_spacing"),opt("justification")}},
 {icon="appbar.textsize",options={opt("font_size"),opt("text_wrap")}},
 {icon="appbar.contrast",options={opt("contrast"),opt("quality")}},
 {icon="appbar.settings",options={opt("doc_language"),opt("forced_ocr")}},
}
local function drawerFor(options, paging, lang)
 G_reader_settings.data={language=lang or "en"}
 local ui=readerUI()
 local configurable={}; for _,panel in ipairs(options) do for _,o in ipairs(panel.options) do configurable[o.name]=1 end end
 ui.config={options=options,configurable=configurable,document=ui.document}
 function ui.config:onShowConfigMenu() end
 if paging then ui.paging={} end
 local pm=ui.menu
 function pm:setUpdateItemTable() self.tab_item_table=MenuSorter:mergeAndSort("reader", readerItems(paging), R_ORDER) end
 local p=Plugin:new{ui=ui}; p:onKindleBottomDrawer(); return p, p.bottom_drawer
end
local function tabSummary(d)
 local out={}
 for _,tab in ipairs(d.tabs) do
  local parts={}
  for _,e in ipairs(tab) do parts[#parts+1]=e.kd_caption and ("#"..e.kd_caption) or e.kd_row and ("@"..e.kd_row) or e.name end
  out[#out+1]=tab.title..":"..table.concat(parts,",")
 end
 return out
end
local p1,d1=drawerFor(CRE,false)
local t=tabSummary(d1)
assert(t[1]=="Font:@change_font,font_size,font_base_weight,font_gamma,font_fine_tune,word_spacing,embedded_fonts,#Fonts and typography,@font_family,@typography,@font_settings", t[1])
assert(t[2]=="Layout:rotation_mode,visible_pages,h_page_margins,#Book styles,embedded_css", t[2])
assert(t[3]=="Page:view_mode,line_spacing,#Status bar and pages,@status_bar,status_line,@page_map", t[3])
assert(t[4]=="Reading:#For all books,@page_turns,@links,@highlight_options,@selection_text,@autoturn", t[4])
assert(t[5]=="More:smooth_scaling,#Contents and bookmarks,@navi_settings,@bookmarks_settings,#Document,@document_settings", t[5])
local seen={}; for _,tab in ipairs(d1.tabs) do for _,e in ipairs(tab) do if e.name then assert(not seen[e.name]); seen[e.name]=true end end end
for _,panel in ipairs(CRE) do for _,o in ipairs(panel.options) do assert(seen[o.name], o.name) end end
-- empty captions are dropped when rows are hidden
d1:selectTab(2); assert(d1.rows[#d1.rows].name=="embedded_css" and d1.rows[#d1.rows-1].kd_caption)
-- moved rows: tap opens the KOReader submenu inline, Back returns; host is touchmenu_instance
d1:selectTab(4)
local function rowY(d,pred) for _,row in ipairs(d.page_rows) do if pred(row.option) then return row end end end
local pt=rowY(d1,function(o) return o.kd_row=="page_turns" end)
d1:onBottom_tap(nil,{pos={x=300*d1.scale,y=d1.top+(pt.y+30)*d1.scale}})
assert(d1.inline_panel and d1.inline_panel.kind=="menu" and d1.inline_panel.title=="Page turns")
local host=d1.menu_host; assert(host.item_table==d1.inline_panel.items and #host.item_table_stack==0)
local inv=d1.page_rows[1]; assert(inv.option.kind=="menuitem")
d1:onBottom_tap(nil,{pos={x=660*d1.scale,y=d1.top+(inv.y+30)*d1.scale}})
assert(d1.inline_panel and d1.inline_panel.kind=="menu", "check item stays open")
painted={}; d1:paintTo(bb)
local function found(pred) for _,v in ipairs(painted) do if pred(v) then return v end end end
assert(found(function(v) return v.kind=="text" and v.text=="‹ Back" end) and found(function(v) return v.kind=="image" and v.file:find("switch%-off") end))
d1:onBottom_tap(nil,{pos={x=60*d1.scale,y=d1.top+25*d1.scale}}); assert(not d1.inline_panel and d1.panel_index==4 and not host.item_table)
-- autoturn row is a switch: tapping the switch runs it in place
local at=rowY(d1,function(o) return o.kd_row=="autoturn" end)
painted={}; d1:paintTo(bb); assert(found(function(v) return v.kind=="text" and v.text=="FOR ALL BOOKS" end))
-- hold on a moved row without help does nothing; with help_text shows it inline
at.option.kd_item.help_text="Turns pages by itself"
d1:onBottom_hold(nil,{pos={x=100*d1.scale,y=d1.top+(at.y+30)*d1.scale}})
assert(d1.inline_panel and d1.inline_panel.kind=="info" and d1.inline_panel.message=="Turns pages by itself")
d1:backInline()
-- a radio submenu inline: Font list
d1:selectTab(1); local cf=rowY(d1,function(o) return o.kd_row=="change_font" end)
d1:onBottom_tap(nil,{pos={x=300*d1.scale,y=d1.top+(cf.y+30)*d1.scale}})
assert(d1.inline_panel.kind=="menu" and #d1.inline_panel.items==1 and d1.page_rows[1].option.item.radio)
d1:onClose(); assert(not d1.inline_panel and p1.bottom_drawer==d1)
-- menu search reaches drawer rows and opens them inside the drawer
p1:onKindleSettingsMenu(); local sm=p1.settings_menu; assert(sm and not p1.bottom_drawer)
local hit; for _,e in ipairs(sm:search("invert")) do if e.drawer_tab=="reading" then hit=e end end
assert(hit and hit.path=="Bottom drawer › Reading › Page turns", hit and hit.path)
sm:openFound(hit); d1=p1.bottom_drawer
assert(not p1.settings_menu and d1 and d1.panel_index==4 and d1.inline_panel.title=="Page turns")
p1:onCloseWidget()
local p2,d2=drawerFor(KOPT,true)
t=tabSummary(d2)
assert(t[1]=="Image:contrast,text_wrap,#When reflowing,font_size,line_spacing,justification,quality", t[1])
assert(t[2]=="Layout:rotation_mode,trim_page,page_margin", t[2])
assert(t[3]=="Page:zoom_mode_type,page_scroll,#Status bar and pages,@status_bar", t[3])
assert(t[4]:sub(1,22)=="Reading:#For all books", t[4])
assert(t[5]=="More:doc_language,forced_ocr,#Contents and bookmarks,@navi_settings,@bookmarks_settings,#Document,@document_settings", t[5])
p2:onCloseWidget()
-- five titles plus "‹ Back" fit the header in both orientations and languages
for _,lang in ipairs({"en","ru"}) do
 for _,size in ipairs({{1072,1448},{1448,1072}}) do
  screen.w,screen.h=size[1],size[2]
  for _,options in ipairs({CRE,KOPT}) do
   local p,d=drawerFor(options,options==KOPT,lang); d.return_callback=function() end
   painted={}; d:paintTo(bb)
   local left,slot=d:tabSlots(); local fs=d:tabFontSize(slot)
   assert(#d.tabs==5 and left+5*slot<=630 and fs>=17, lang..fs)
   for i,tab in ipairs(d.tabs) do
    local w=require("drawer").measure(d,tab.title,fs,true); assert(w<=slot-8, tab.title)
    local center=left+(i-0.5)*slot; assert(center-w/2>=left+(i-1)*slot and center+w/2<=left+i*slot)
   end
   -- tap hit areas match the painted slots
   d:onBottom_tap(nil,{pos={x=(left+4.5*slot)*d.scale,y=d.top+25*d.scale}}); assert(d.panel_index==5)
   p:onCloseWidget()
  end
 end
end
screen.w,screen.h=1072,1448; G_reader_settings.data={language="en"}
Layout.uninstallSortGuard()
-- Leave the real widgets to later scripts (tests/bottom.py loads KOReader's ConfigDialog).
for name,value in pairs(saved) do package.loaded[name]=value or nil end
package.loaded.bottomdrawer=nil; package.loaded.inlinepanels=nil
print("PASS: drawer tabs for rolling/paging, moved options and rows, inline KOReader submenus with Back, host as touchmenu_instance, 5 tabs fit en/ru portrait/landscape")
