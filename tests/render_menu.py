"""Preview the Kindle-style top menu from its actual paint calls (Arial metrics, resvg; not KOReader UI).

The tab tables imitate KOReader's file browser menu; texts are sample strings, not KOReader's catalogue.
"""
import base64
from html import escape
from pathlib import Path
import runpy
from PIL import ImageFont
import resvg_py
lua = runpy.run_path('tests/run.py')['lua']
font_dir = Path('/System/Library/Fonts/Supplemental')
def measure(text, size, bold):
    return ImageFont.truetype(str(font_dir / ('Arial Bold.ttf' if bold else 'Arial.ttf')), round(size)).getlength(text)
lua.globals().measure = measure
lua.execute(r'''
local Text=require("ui/widget/textwidget")
local function fit(self)
 local text=self.text
 if self.max_width and measure(text,self.face,self.bold)>self.max_width then
  -- TextWidget truncates with an ellipsis; drop whole UTF-8 characters.
  while #text>0 and measure(text.."…",self.face,self.bold)>self.max_width do
   text=text:gsub("[%z\1-\127\194-\244][\128-\191]*$","")
  end
  return text.."…",true
 end
 return text,false
end
function Text:getSize() local t=fit(self); return {w=measure(t,self.face,self.bold),h=self.face*1.2} end
function Text:isTruncated() local _,t=fit(self); return t end
function Text:paintTo(bb,x,y)
 painted[#painted+1]={kind="text",text=(fit(self)),x=x,y=y,size=self.face,bold=self.bold,color=self.fgcolor}
end
screen.w=1072; screen.h=1448; screen.dpi_scale=2; device.wifi=true; network.on=true; device.touch=true
function power:getCapacity() return 67 end
''')
lua.execute(r'''
function previewUI(lang)
 local ru=lang=="ru"
 local function T(en,r) return ru and r or en end
 local ui=newUI(); ui.document=nil
 local menu=ui.menu
 local function radio(options,selected)
  local t={}
  for i,o in ipairs(options) do t[i]={text=o,radio=true,checked_func=function() return i==selected end,callback=function() end} end
  return t
 end
 local function sub(...) local t={} for i,v in ipairs({...}) do t[i]={text=v,callback=function() end} end return t end
 local function check(text,on,extra) local t={text=text,checked_func=function() return on end,callback=function() end}
  for k,v in pairs(extra or {}) do t[k]=v end; return t end
 function menu:setUpdateItemTable()
  local files={icon="appbar.filebrowser",id="filemanager_settings",
   {text=T("Display mode","Режим отображения"),sub_item_table=radio(ru and {"классический (только имена файлов)","мозаика с обложками","список с обложками и метаданными","список с метаданными, без изображений","список с обложками и именами файлов"} or {"classic (filename only)","mosaic with cover images","list with cover images and metadata","list with metadata, no images","list with cover images and filenames"},3)},
   {text=T("File browser settings","Настройки файлового менеджера"),separator=true,sub_item_table=sub("a")},
   {text=T("Sort by: name","Сортировка: по имени"),sub_item_table=radio({"name","date"},1)},
   check(T("Reverse sorting","Обратная сортировка"),false),
   check(T("Folders and files mixed","Папки и файлы вперемешку"),false,{id="sort_mixed",separator=true}),
   {id="start_with",text=T("Start with: file browser","Начинать с: файлового менеджера"),sub_item_table=radio({"x"},1)},
  }
  local langs={"Bahasa Indonesia","Català","Čeština","Dansk","Deutsch","English","Español","Русский"}
  local general={icon="appbar.settings",id="setting",
   {text=T("Frontlight","Подсветка"),callback=function() end},
   check(T("Night mode","Ночной режим"),false,{separator=true}),
   {text=T("Network","Сеть"),sub_item_table=sub("a")},
   {text=T("Screen","Экран"),separator=true,sub_item_table=sub("a")},
   {text=T("Taps and gestures","Касания и жесты"),sub_item_table=sub("a")},
   {text=T("Navigation","Навигация"),sub_item_table=sub("a")},
   {text=T("Document","Документ"),separator=true,sub_item_table=sub("a")},
   {text=T("Language","Язык"),sub_item_table=radio(langs,ru and 8 or 6)},
   {text=T("Device","Устройство"),sub_item_table=sub("a")},
   {id="screen_dpi",text=T("Screen DPI","DPI экрана"),sub_item_table=radio({T("auto","авто"),T("custom","свой")},1)},
   check(T("Color rendering","Цветной рендеринг"),false,{enabled_func=function() return false end}),
   {text=T("Autosuspend timeout: 15 min","Автоматический сон: 15 мин"),keep_menu_open=true,callback=function() end},
  }
  local items={}; self.plugin:addToMainMenu(items); items.kindle_drawer.id="kindle_drawer"
  local tools={icon="appbar.tools",id="tools",
   {text=T("Reading statistics","Статистика чтения"),sub_item_table=sub("a")},
   {id="calibre",text="Calibre",sub_item_table=sub("a")},
   {id="profiles",text=T("Profiles","Профили"),sub_item_table=sub("a")},
   {id="news_downloader",text=T("News downloader","Загрузчик новостей"),separator=true,sub_item_table=sub("a")},
   {id="more_tools",text=T("More tools","Другие инструменты"),sub_item_table={items.kindle_drawer}},
  }
  local search={icon="appbar.search",id="search",
   {text=T("Dictionary lookup","Поиск в словаре"),callback=function() end},
   {id="opds",text=T("OPDS catalog","Каталог OPDS"),callback=function() end},
  }
  local main={icon="appbar.menu",id="main",
   {text=T("History","История"),callback=function() end},
   {text=T("Exit","Выход"),sub_item_table=sub("a")},
  }
  self.tab_item_table={files,general,tools,search,main}
 end
 return ui
end
''')
out = Path('dist')
cases = [(lang, v) for lang in ['en', 'ru'] for v in ['root', 'files', 'long', 'radio']] + [('en', 'files-landscape')]
for lang, name in cases:
        variant = name.split('-')[0]
        width, height = (1448, 1072) if name.endswith('landscape') else (1072, 1448)
        lua.globals().locale, lua.globals().variant = lang, variant
        lua.globals().preview_w, lua.globals().preview_h = width, height
        lua.execute('''
G_reader_settings.data={language=locale}; screen.night_mode=false; painted={}; screen.w=preview_w; screen.h=preview_h
local ui=previewUI(locale); local p=Plugin:new{ui=ui}; ui.menu.plugin=p
ui.menu:onShowMenu(); local m=p.settings_menu
if variant=="files" then m:openTab(1)
elseif variant=="long" then m:openTab(2); m:scrollTo(3*56+11)
elseif variant=="radio" then m:openTab(1); m:onMenuSelect(m.item_table[1]) end
painted={}; m:paintTo(bb); p:onCloseWidget()
''')
        parts = [f'<svg xmlns="http://www.w3.org/2000/svg" width="{width}" height="{height}"><rect width="{width}" height="{height}" fill="#eee"/>']
        for item in lua.globals().painted.values():
            x, y = item['x'], item['y']
            if item['kind'] == 'rect':
                parts.append(f'<rect x="{x}" y="{y}" width="{item["w"]}" height="{item["h"]}" fill="{item["color"]}"/>')
            elif item['kind'] == 'text':
                fill = item['color'] or 'black'
                parts.append(f'<text x="{x}" y="{y+item["size"]*0.93}" font-family="Arial" font-size="{item["size"]}" fill="{fill}" font-weight="{700 if item["bold"] else 400}">{escape(item["text"])}</text>')
            elif item['kind'] == 'image':
                data = base64.b64encode(Path(item['file']).read_bytes()).decode()
                parts.append(f'<image x="{x}" y="{y}" width="{item["w"]}" height="{item["h"]}" href="data:image/svg+xml;base64,{data}"/>')
        parts.append('</svg>')
        svg = ''.join(parts)
        (out / f'menu-{name}-{lang}.svg').write_text(svg)
        (out / f'menu-{name}-{lang}.png').write_bytes(resvg_py.svg_to_bytes(svg_string=svg))
print('Wrote dist/menu-{root,files,long,radio}-{en,ru}.png and dist/menu-files-landscape-en.png')
