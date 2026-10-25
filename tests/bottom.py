"""Exercise the new drawer against real KOReader option/application code.
Pass a KOReader checkout; hardware/widget rendering dependencies are doubles.
"""
import sys
import runpy
from pathlib import Path
lua = runpy.run_path('tests/run.py')['lua']
root = Path(sys.argv[1] if len(sys.argv)>1 else '/tmp/kindle-drawer-koreader')
lua.globals().koreader_root = str(root)
lua.execute(r'''
local Base=require("ui/widget/container/widgetcontainer")
package.preload["apps/filemanager/filemanager"]=function() return {instance={onHome=function(self) self.home_calls=(self.home_calls or 0)+1 end}} end
for _,name in ipairs({"button", "buttonprogresswidget", "fixedtextwidget", "focusmanager", "iconbutton", "iconwidget", "linewidget", "toggleswitch", "horizontalgroup", "horizontalspan", "verticalgroup", "verticalspan", "confirmbox"}) do
 package.preload["ui/widget/"..name]=function() return Base end
end
for _,name in ipairs({"bottomcontainer", "centercontainer", "framecontainer", "rightcontainer", "underlinecontainer"}) do
 package.preload["ui/widget/container/"..name]=function() return Base end
end
local TextBox=Base:extend{}
function TextBox:getAllLineCount() return math.max(1,math.ceil(#self.text/math.max(1,self.width/(self.face*0.5)))) end
function TextBox:getVisLineCount() return math.max(1,math.floor(self.height/(self.face*1.3))) end
function TextBox:scrollToRatio(ratio) self.ratio=ratio end
function TextBox:free() self.freed=true end
function TextBox:paintTo() end
package.preload["ui/widget/textboxwidget"]=function() return TextBox end
package.preload["document/credocument"]=function() return {engineInit=function() return {getFontFaceAvailableWeights=function() return {400,700} end} end} end
package.preload["ui/size"]=function() return {padding={button=2},line={},margin={}} end
package.preload["logger"]=function() return {dbg=function() end,info=function() end,warn=function() end,err=function() end} end
package.preload["ffi/serpent"]=function() return {block=function() return "table" end} end
package.preload["ui/widget/notification"]=function() return {setNotifySource=function() end,resetNotifySource=function() end} end
package.preload["util"]=function() return {tableDeepCopy=function(v) return v end, arrayReverse=function(t) return t end} end
package.preload["ffi/util"]=function() return {template=function(s,...) local a={...}; return (s:gsub("%%(%d)",function(i) return tostring(a[tonumber(i)]) end)) end} end
package.preload["gettext"]=function() return setmetatable({pgettext=function(_,s) return s end},{__call=function(_,s) return s end}) end
local defaults=dofile(koreader_root.."/defaults.lua")
G_defaults={readSetting=function(_,k) return defaults[k] end}
function device:hasDPad() return false end
function device:isTouchDevice() return true end
function device:hasMultitouch() return true end
function device:hasEinkScreen() return true end
function device:canHWDither() return false end
function device:hasKeys() return false end
function device:hasColorScreen() return false end
function screen:isColorEnabled() return false end
function screen:getWidth() return self.w end
function screen:getHeight() return self.h end
function screen:getRotationMode() return 0 end
function screen:scaleByDPI(v) return v end
function manager:tickAfterNext(fn) fn() end
function manager:scheduleIn(_,fn) self.pending=fn end
package.preload["ui/data/optionsutil"]=function() return {formatFlexSize=function(v,u) return tostring(v).." "..u end,rotation_modes={0,1,2,3},rotation_labels={"Portrait","Landscape","Inverted","Landscape inverted"},showValues=function() end,enableIfEquals=function(c,k,v) return c[k]==v end} end
package.preload["ui/bidi"]=function() return {mirroredUILayout=function() return false end} end
package.preload["ui/data/isolanguage"]=function() return {getLocalizedLanguage=function(_,v) return v end} end
package.preload["ui/data/ocr"]=function() return {getOCRLangs=function() return {"eng"} end} end
package.preload["ui/widget/configdialog"]=function() return dofile(koreader_root.."/frontend/ui/widget/configdialog.lua") end
package.preload["ui/widget/spinwidget"]=function() return Base end
package.preload["ui/widget/doublespinwidget"]=function() return Base end
package.loaded["ui/event"]={new=function(_,name,...) return {name=name,args={...}} end}
-- main.lua has a reference to the old Event module: reload it before integration checks.
package.loaded.main=nil; Plugin=require("main")
function makeReader(options)
 local ui=newUI()
 local configurable={}
 for _,panel in ipairs(options) do for _,o in ipairs(panel.options) do configurable[o.name]=o.default_value end end
 local document={configurable=configurable,info={has_pages=false},getVisiblePageCount=function() return 1 end,getFontFace=function() return "Bookerly" end,getEmbeddedFontList=function() return {} end}
 ui.document=document
 ui.config={options=options,configurable=configurable,document=document,original_calls=0}
 function ui.config:onShowConfigMenu() self.original_calls=self.original_calls+1; return true end
 function ui.config:onCloseConfigMenu() if self.config_dialog then self.config_dialog:closeDialog() end end
 function ui:handleEvent(e)
  self.events[#self.events+1]=e.name
  if e.name=="ConfigChange" then configurable[e.args[1]]=e.args[2] end
  if e.args and type(e.args[2])=="function" then e.args[2]() end
 end
 return ui
end
cre=dofile(koreader_root.."/frontend/ui/data/creoptions.lua")
kopt=dofile(koreader_root.."/frontend/ui/data/koptoptions.lua")
''')
lua.execute(r'''
for _,options in ipairs({cre,kopt}) do
 G_reader_settings.data={}
 local ui=makeReader(options)
 local original=ui.config.onShowConfigMenu
 local p=Plugin:new{ui=ui}
 ui.config:onShowConfigMenu(); local d=p.bottom_drawer
 assert(d and ui.config.config_dialog==d and ui.config.original_calls==0)
 local seen,count={},0
 for _,tab in ipairs(d.tabs) do for _,o in ipairs(tab) do if o.name then seen[o]=true; count=count+1 end end end
 assert(#d.tabs==5)
 local expected=0
 for _,panel in ipairs(options) do for _,o in ipairs(panel.options) do assert(seen[o]); expected=expected+1 end end
 assert(count==expected,"all options mapped once")
 local function tabOf(name) for i,tab in ipairs(d.tabs) do for _,o in ipairs(tab) do if o.name==name then return tab.key end end end end
 if options==cre then
  assert(d.tabs[1].title=="Font" and d.tabs[4].title=="Reading" and d.tabs[4][1].kd_caption=="For all books")
  assert(tabOf("embedded_fonts")=="font" and tabOf("embedded_css")=="layout" and tabOf("status_line")=="page")
  assert(tabOf("font_size")=="font" and tabOf("rotation_mode")=="layout" and tabOf("view_mode")=="page" and tabOf("nightmode_images")=="more")
 else
  assert(d.tabs[1].title=="Image" and d.tabs[4].title=="Reading")
  assert(tabOf("contrast")=="image" and tabOf("text_wrap")=="image" and tabOf("font_size")=="image" and tabOf("quality")=="image")
  assert(tabOf("trim_page")=="layout" and tabOf("zoom_mode_type")=="page" and tabOf("page_scroll")=="page" and tabOf("forced_ocr")=="more")
 end
 for tab=1,#d.tabs do
  d:selectTab(tab)
  for page=1,d.pages do
   d.page=page; d:update()
   for _,o in ipairs(d.rows) do d:enabled(o); d:position(o); d:title(o) end
  end
 end
 d:selectTab(1)
 ui.config.configurable.text_wrap=1
 local font=d:findOptionByName("font_size")
 d:choose(font,2); assert(ui.config.configurable.font_size==font.values[2])
 local fine=d:findOptionByName("font_fine_tune")
 if fine.more_options then
  d:more(fine); assert(d.inline_panel.fields[1].min==12)
  d.inline_panel.fields[1].value=27.5; d:applyEditor(d.inline_panel); assert(ui.config.configurable.font_size==27.5)
  d:backInline()
 end
 local old=ui.config.configurable.font_size
 d:onBottom_pan(nil,{start_pos={x=10,y=0},pos={x=500,y=1000}})
 d:onBottom_pan_release(nil,{pos={x=500,y=1000}})
 assert(ui.config.configurable.font_size==old)
 p:showOriginalBottom(); assert(not p.bottom_drawer and not ui.config.config_dialog and ui.config.original_calls==1)
 assert(ui.events[#ui.events]=="RestoreHinting")
 p.settings.bottom_enabled=false; ui.config:onShowConfigMenu(); assert(not p.bottom_drawer and ui.config.original_calls==2)
 p.settings.bottom_enabled=true; ui.config:onShowConfigMenu(); assert(p.bottom_drawer)
 p:onKindleDrawer(); assert(not p.bottom_drawer and p.drawer)
 ui.config:onShowConfigMenu(); assert(p.bottom_drawer and not p.drawer)
 p:onSuspend(); assert(not p.bottom_drawer and not ui.config.config_dialog)
 p:onCloseWidget(); assert(ui.config.onShowConfigMenu==original)
end
print("PASS: real CRE/KOPT schemas in five tabs (embedded fonts/styles and alt status bar moved), native ConfigDialog apply/pickers, config hook, mutual exclusion, teardown")
''')
lua.execute(r'''
G_reader_settings.data={kindle_drawer={full_refresh=true}}
local ui=makeReader(cre); local p=Plugin:new{ui=ui}; p:onKindleBottomDrawer(); local d=p.bottom_drawer
assert(manager.last_show.refresh=="full")
local font=d:findOptionByName("font_size")
local pos={x=500*d.scale,y=d.top+110*d.scale}
d:onBottom_pan(nil,{start_pos=pos,pos=pos})
d:onBottom_swipe(nil,{direction="west",end_pos={x=640*d.scale,y=pos.y}})
assert(ui.config.configurable.font_size==font.values[#font.values] and d.page==1)
local held
local oldDefault=d.onMakeDefault
d.onMakeDefault=function(_,name,title,values,labels,index) held=index end
d:onBottom_hold(nil,{pos={x=350*d.scale,y=pos.y}}); assert(held==1)
d.onMakeDefault=oldDefault
for _,size in ipairs({{1072,1448},{1448,1072},{600,800}}) do
 screen.w,screen.h=size[1],size[2]; d:update()
 assert(d.top>=0 and d.top+d.height==screen.h)
 for _,row in ipairs(d.page_rows) do assert(row.y+row.height<=d.height/d.scale-50) end
end
p:onSuspend(); assert(manager.last_dirty.refresh=="full")
local touch=device.isTouchDevice; device.isTouchDevice=function() return false end
ui.config:onShowConfigMenu(); assert(not p.bottom_drawer and ui.config.original_calls==1)
p:onKindleBottomDrawer(); assert(not p.bottom_drawer and ui.config.original_calls==2)
device.isTouchDevice=touch
p:onCloseWidget(); screen.w=1072; screen.h=1448
print("PASS: review regressions (fast slider swipe, held preset, non-touch fallback), full refresh, geometry")
''')
lua.execute(r'''
for _,full in ipairs({false,true}) do
 G_reader_settings.data={kindle_drawer={full_refresh=full}}
 local p=Plugin:new{ui=makeReader(cre)};p:onQuickActionsPanel()
 assert(manager.last_show.refresh=="ui","quick actions never full-refreshes on open")
 p.quick_actions_panel:onClose()
 assert(manager.last_dirty.refresh==(full and "full" or "partial"),"quick actions honors full refresh on close")
 p:onCloseWidget()
end
print("PASS: quick actions uses UI refresh on open and the configured refresh on close")
''')
lua.execute(r'''
G_reader_settings.data={}; local p=Plugin:new{ui=makeReader(cre)}; p:onKindleBottomDrawer(); local d=p.bottom_drawer
local switch=d:findOptionByName("embedded_css")
d:showChoices(switch)
local old=d:current(switch)
assert(d.choice_option==switch and #d.page_rows==2)
d:onBottom_hold(nil,{pos={x=660*d.scale,y=d.top+95*d.scale}})
d:inlineFooter(210)
assert(G_reader_settings.data.copt_embedded_css==switch.values[1] and d:current(switch)==old)
p:onCloseWidget()
print("PASS: switch defaults remain accessible without applying the value")
''')
lua.execute(r'''
G_reader_settings.data={}; local p=Plugin:new{ui=makeReader(cre)}; p:onKindleBottomDrawer(); local d=p.bottom_drawer
local font=d:findOptionByName("font_size"); d.configurable.font_size=70
d:adjust(font,677); assert(d.configurable.font_size==70)
d.configurable.font_size=19; d:adjust(font,677); assert(d.configurable.font_size==20)
local weight=d:findOptionByName("font_base_weight"); d.configurable.font_base_weight=-2
d:adjust(weight,310); assert(d.configurable.font_base_weight==-2)
d:adjust(weight,677); assert(d.configurable.font_base_weight==-1)
p:onCloseWidget()
print("PASS: custom slider values never move opposite to +/- and do not skip the next preset")
''')
# Use KOReader's actual stacking function, not a fake which always replaces shown.
manager_source = (root/'frontend/ui/uimanager.lua').read_text()
start = manager_source.index('function UIManager:show(')
end = manager_source.index('\nend\n', start)+5
lua.globals().native_show_source = manager_source[start:end]
lua.execute(r'''
local Base=require("ui/widget/container/widgetcontainer")
function Base:handleEvent(e)
 local callback=self["on"..e.name]; if callback then return callback(self) end
end
local originalShow=manager.show
local originalClose=manager.close
local inputs={}
local source="local UIManager, Event, Input, logger = ...\n"..native_show_source.."\nreturn UIManager.show"
assert(loadstring(source))(manager,require("ui/event"),inputs,{dbg=function() end})
manager._window_stack={}
function manager:close(w)
 for i=#self._window_stack,1,-1 do if self._window_stack[i].widget==w then table.remove(self._window_stack,i) end end
 if w.onCloseWidget then w:onCloseWidget() end
end
G_reader_settings.data={}; local p=Plugin:new{ui=makeReader(cre)}; p:onKindleBottomDrawer(); local d=p.bottom_drawer
assert(#manager._window_stack==1 and not d.modal)
d:selectTab(3)
local option=d:findOptionByName("block_rendering_mode")
local old=d:current(option)
d:showChoices(option)
assert(#manager._window_stack==1,"choice is not an extra window")
assert(d.choice_option==option and #d.page_rows==#option.toggle)
-- A header tap on the old tabs cannot open a second chooser.
d:onBottom_tap(nil,{pos={x=450*d.scale,y=d.top+25*d.scale}})
assert(d.choice_option==option and #manager._window_stack==1)
-- Back cancels without changing the setting or the tab.
d:onBottom_tap(nil,{pos={x=60*d.scale,y=d.top+25*d.scale}})
assert(not d.choice_option and d.panel_index==3 and d:current(option)==old)
for i=1,#option.toggle do
 d:showChoices(option)
 local row=d.page_rows[i]
 d:onBottom_tap(nil,{pos={x=300*d.scale,y=d.top+(row.y+30)*d.scale}})
 assert(d:current(option)==option.values[i] and not d.choice_option and #manager._window_stack==1)
end
-- Choice pagination and Back from the second main page.
d:selectTab(1); d:turnPage(1); local parent=d.page
local big={name="test_choices",values={},toggle={}}
for i=1,15 do big.values[i]=i; big.toggle[i]="Choice "..i end
d:showChoices(big); assert(d.pages>1)
d:onBottom_swipe(nil,{direction="west"}); assert(d.page==2)
local entry=d.page_rows[1]
d:onBottom_tap(nil,{pos={x=200*d.scale,y=d.top+(entry.y+20)*d.scale}})
assert(d.configurable.test_choices==entry.option.choice_index and d.page==parent and not d.choice_option)
d:showChoices(big); d:onClose(); assert(not d.choice_option and p.bottom_drawer==d)
-- A native precise-value picker must receive input above the drawer.
local fine=d:findOptionByName("font_fine_tune")
d:more(fine)
assert(#manager._window_stack==1 and d.inline_panel.kind=="editor")
assert(d.inline_panel.fields[1].min==12)
d:backInline()
-- A native default confirmation must also appear above it.
d:showChoices(option)
d:onBottom_hold(nil,{pos={x=200*d.scale,y=d.top+95*d.scale}})
assert(#manager._window_stack==1 and d.inline_panel.kind=="confirm")
d:backInline()
p:onCloseWidget(); assert(#manager._window_stack==0)
manager.show=originalShow; manager.close=originalClose
print("PASS: native UIManager stack, inline choice/Back/cancel/apply/pagination, inline picker and confirmation without extra windows")
''')
lua.execute(r'''
for _,options in ipairs({cre,kopt}) do
 for _,size in ipairs({{1072,1448},{1448,1072},{600,800}}) do
  screen.w,screen.h=size[1],size[2]
  G_reader_settings.data={}; local p=Plugin:new{ui=makeReader(options)}; p:onKindleBottomDrawer(); local d=p.bottom_drawer
  for tab=1,#d.tabs do
   d:selectTab(tab)
   local found={}
   for page=1,d.pages do
    d.page=page; d:update()
    local last=70
    for _,row in ipairs(d.page_rows) do
     assert(row.y==last and row.y+row.height<=d.height/d.scale-50)
     assert(not found[row.option]); found[row.option]=true
     local point={x=350*d.scale,y=d.top+(row.y+row.height/2)*d.scale}
     assert(d:rowAt(point)==row.option)
     if d:isSlider(row.option) then assert(row.height==126 and 18+17<77-18) end
     last=row.y+row.height
    end
   end
   for _,o in ipairs(d.rows) do assert(found[o],"every visible row is reachable once") end
  end
  p:onCloseWidget()
 end
end
screen.w=1072;screen.h=1448
print("PASS: variable row heights, slider headroom, all pages and hit targets in CRE/KOPT portrait/landscape")
''')
lua.execute(r'''
-- All precise editors use original schemas and never show another window.
local show=manager.show
local count=0
manager.show=function(...) count=count+1; return show(...) end
for _,options in ipairs({cre,kopt}) do
 G_reader_settings.data={language="en"}
 local p=Plugin:new{ui=makeReader(options)};p:onKindleBottomDrawer();local d=p.bottom_drawer
 d.configurable.text_wrap=1
 local windows=count
 for _,tab in ipairs(options) do for _,o in ipairs(tab.options) do
  if o.more_options and d:enabled(o) then
   local parent=d.page
   d:more(o);local panel=d.inline_panel
   assert(panel.kind=="editor",o.name)
   for _,f in ipairs(panel.fields) do
    assert(type(f.value)=="number" and type(f.min)=="number" and type(f.max)=="number",o.name)
    d:adjustField(f,1,true)
    assert(f.value>=f.min and f.value<=f.max)
    d:editField(f)
    if f.value_table then
     d:inlineTap(d.inline_panel.rows[1],100,20)
     assert(f.value==1)
    else
     d.inline_panel.input=tostring(f.max+1);d:inlineFooter(375)
     assert(d.inline_panel.error and d.inline_panel.kind=="number")
     d.inline_panel.input=tostring(f.min);d:inlineFooter(375)
     assert(f.value==f.min and d.inline_panel==panel)
    end
   end
   local before=#p.ui.events
   d:saveEditorDefault(panel);assert(d.inline_panel.kind=="confirm")
   d:inlineFooter(210);assert(d.inline_panel==panel and #p.ui.events==before)
   local expected=d:editorValue(panel)
   d:applyEditor(panel)
   if panel.params.names then
    for i,key in ipairs(panel.params.names) do assert(d.configurable[key]==expected[i]) end
   elseif type(expected)=="table" then
    for i,v in ipairs(expected) do assert(d.configurable[panel.name][i]==v) end
   else assert(d.configurable[panel.name]==expected) end
   d:backInline();assert(not d.inline_panel and d.page==parent)
  end
 end end
 assert(count==windows,"no editor/default/keypad opens a window")
 p:onCloseWidget()
end
manager.show=show
-- Drafts are independent, Back cancels, nested panels retain drafts.
G_reader_settings.data={language="en"};local p=Plugin:new{ui=makeReader(cre)};p:onKindleBottomDrawer();local d=p.bottom_drawer
local o=d:findOptionByName("h_page_margins");local original=d.configurable[o.name][1]
d:more(o);local panel=d.inline_panel;panel.fields[1].value=original+1
assert(d.configurable[o.name][1]==original)
d:editField(panel.fields[1]);d.inline_panel.input="99";d:onClose()
assert(d.inline_panel==panel and panel.fields[1].value==original+1)
d:saveEditorDefault(panel);d:onClose();assert(d.inline_panel==panel)
d:onClose();assert(d.configurable[o.name][1]==original)
-- Native fine-size help retains units for presets and PDF explanation.
d:showHelp(d:findOptionByName("font_fine_tune"));assert(d.inline_panel.message:find("pt",1,true));d:onClose()
-- Canonical font-size defaults and gamma indexes survive aliases.
d:more(d:findOptionByName("font_fine_tune"));assert(d.inline_panel.fields[1].default==d:findOptionByName("font_size").default_value);d:onClose()
d:more(d:findOptionByName("font_gamma"));panel=d.inline_panel
panel.fields[1].value=11;d:applyEditor(panel);assert(d.configurable.font_gamma==10);d:onClose()
-- Help pages, resources and close-before-apply safety.
d:showInfo("Help",string.rep("Long help text. ",1000));local box=d.inline_panel.box
assert(d.inline_panel.text_pages>1);d:turnPage(1);assert(d.inline_panel.text_page==2)
d:onClose();assert(box.freed)
d:more(o);panel=d.inline_panel
local tick=manager.tickAfterNext;local pending
manager.tickAfterNext=function(_,fn) pending=fn end
d:applyEditor(panel);p:onCloseWidget();local events=#p.ui.events;pending();assert(#p.ui.events==events)
manager.tickAfterNext=tick
print("PASS: every available CRE/KOPT numeric editor, draft cancellation, defaults, bounds, gamma indexes, help pagination and delayed-close safety")
''')
lua.execute(r'''
for _,size in ipairs({{1072,1448},{1448,1072},{600,800}}) do
 screen.w,screen.h=size[1],size[2]
 for _,action in ipairs({{80,79,"Home"},{448,79,"ShowToc"},{516,79,"ShowBookmark"},{584,79,"ShowPageBrowser"},{375,-70,"ShowSkimtoDialog"}}) do
  G_reader_settings.data={};local ui=makeReader(cre)
  function ui:getCurrentPage() return 369 end
  function ui.document:getPageCount() return 810 end
  ui.doc_props={display_title="Test book"}
  local p=Plugin:new{ui=ui};p:onQuickActionsPanel();local d=p.quick_actions_panel
  assert(d and not p.bottom_drawer and not ui.config.config_dialog)
  assert(182+142<d.dimen.h/d.scale,"panels leave space for the book")
  local page,total,ratio=d:bookProgress();assert(page==369 and total==810 and ratio==369/810)
  d:onQuick_swipe(nil,{direction="west"});assert(p.quick_actions_panel==d)
  local original=ui.handleEvent
  function ui:handleEvent(e)
   if e.name==action[3] then assert(not p.quick_actions_panel,"drawer closes before dispatch") end
   return original(self,e)
  end
  local y=action[2]<0 and d.dimen.h/d.scale+action[2] or action[2]
  d:onQuick_tap(nil,{pos={x=action[1]*d.scale,y=y*d.scale}})
  assert(ui.events[#ui.events]==action[3] and not p.quick_actions_panel)
  if action[3]=="Home" then assert(require("apps/filemanager/filemanager").instance.home_calls>0) end
  p:onCloseWidget()
 end
end
screen.w,screen.h=1072,1448
G_reader_settings.data={};local ui=makeReader(cre);ui.doc_props={display_title="Test book"}
function ui:getCurrentPage() return 369 end
function ui.document:getPageCount() return 810 end
local p=Plugin:new{ui=ui};p:onQuickActionsPanel();local d=p.quick_actions_panel
painted={};d:paintTo(bb)
local action_icons=0;local aa,title;local action_divider,content_divider
for _,item in ipairs(painted) do
 if item.kind=="image" and item.file:find("/book-",1,true) and not item.file:find("book-chevron",1,true) then
  action_icons=action_icons+1
  assert(item.w==math.floor(30*d.scale) and item.h==math.floor(30*d.scale),"quick-action icons share one smaller size")
 elseif item.kind=="text" and item.text=="Aa" then aa=item
 elseif item.kind=="text" and item.text=="Test book" then title=item
 elseif item.kind=="rect" and item.y==math.floor(119*d.scale) then action_divider=item
 elseif item.kind=="rect" and item.y==math.floor(179*d.scale) then content_divider=item end
end
assert(action_icons==6 and aa and math.abs(aa.size-22*d.scale)<=1,"Aa matches the action row")
assert(title and title.x==math.floor(26*d.scale),"book title keeps its left alignment")
assert(title.y==math.floor(150*d.scale-title.size/2),"book title is vertically centered in its band")
assert(action_divider and action_divider.h==math.floor(2*d.scale))
assert(content_divider and content_divider.h==math.floor(3*d.scale) and action_divider.h<content_divider.h)
local function tap(x,y) d:onQuick_tap(nil,{pos={x=x*d.scale,y=y*d.scale}}) end
tap(380,79);assert(p.bottom_drawer and not p.quick_actions_panel)
p.bottom_drawer:selectTab(3);p.bottom_drawer:onClose();assert(p.quick_actions_panel)
d=p.quick_actions_panel;tap(380,79);assert(p.bottom_drawer.panel_index==3)
p.bottom_drawer:onClose();d=p.quick_actions_panel
tap(721,79);assert(not p.quick_actions_panel)
p:onQuickActionsPanel();d=p.quick_actions_panel;tap(375,400);assert(not p.quick_actions_panel)
p:onKindleBottomDrawer();assert(not p.bottom_drawer.return_callback)
p.bottom_drawer:onClose();assert(not p.bottom_drawer and not p.quick_actions_panel)
p:onCloseWidget()
print("PASS: book actions close before dispatch, progress, one-page landscape fit, settings Back, close icon and outside tap")
''')

lua.execute(r'''
G_reader_settings.data={};local ui=makeReader(cre)
ui.simpleui={onSimpleUIGoHomescreen=setmetatable({}, {__call=function() end})}
local p=Plugin:new{ui=ui};p:onQuickActionsPanel()
p.quick_actions_panel:bookAction("Home")
assert(ui.events[#ui.events]=="SimpleUIGoHomescreen" and not p.quick_actions_panel)
p:onCloseWidget()
print("PASS: Home uses SimpleUI homescreen when available, native folder otherwise")
''')

lua.execute(r'''
G_reader_settings.data={}
local ui=makeReader(cre);local p=Plugin:new{ui=ui}
ui.menu:onTapShowMenu({});assert(p.quick_actions_panel and not p.bottom_drawer)
p.quick_actions_panel:onQuick_swipe(nil,{direction="south",pos={x=600,y=30}});assert(p.drawer and not p.quick_actions_panel)
ui.config:onShowConfigMenu();assert(p.bottom_drawer and not p.drawer and not p.quick_actions_panel)
p.settings.enabled=false
ui.menu:onTapShowMenu({});assert(p.quick_actions_panel and not p.bottom_drawer)
p.settings.bottom_enabled=false
p.quick_actions_panel:showLayoutPanel();assert(not p.quick_actions_panel and ui.config.original_calls==1)
p.settings.quick_actions_enabled=false
ui.menu:onTapShowMenu({});assert(ui.menu.original_calls==0 and p.settings_menu and not p.quick_actions_panel)
p.settings.kindle_menu=false
ui.menu:onTapShowMenu({});assert(ui.menu.original_calls==1 and not p.quick_actions_panel)
p.settings.kindle_menu=nil
p.settings.enabled=true
ui.menu:onSwipeShowMenu({direction="south"});assert(p.drawer)
p:onCloseWidget()
print("PASS: independent panel switches, tap/swipe routing and native fallback")
''')
