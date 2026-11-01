"""Preview the Kindle-style top menu from its actual paint calls (Arial metrics, resvg; not KOReader UI).

Menu items imitate KOReader's file browser and reader menus and go through the MenuSorter
double and layout.lua; texts are sample strings, not KOReader's catalogue.
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
-- Sample items in KOReader's shapes and wording; sorted by the MenuSorter double.
function previewUI(lang, reader)
 local ru=lang=="ru"
 local function T(en,r) return ru and r or en end
 local ui=newUI(); ui.document=reader and {} or nil
 local menu=ui.menu
 local function radio(options,selected)
  local t={}
  for i,o in ipairs(options) do t[i]={text=o,radio=true,checked_func=function() return i==selected end,callback=function() end} end
  return t
 end
 local function sub(...) local t={} for i,v in ipairs({...}) do t[i]={text=v,callback=function() end} end return t end
 local function check(text,on,extra) local t={text=text,checked_func=function() return on end,callback=function() end}
  for k,v in pairs(extra or {}) do t[k]=v end; return t end
 local function act(text) return {text=text,callback=function() end} end
 local order={
  ["KOMenu:menu_buttons"]=reader and {"navi","typeset","setting","tools","search","filemanager","main"} or {"filemanager_settings","setting","tools","search","reader","main"},
  filemanager_settings={"filemanager_display_mode","filebrowser_settings","show_filter","sort_by","reverse_sorting","sort_mixed","start_with"},
  navi={"table_of_contents","bookmarks","book_map","page_browser","go_to","skim_to","go_to_previous_location"},
  typeset={"document_settings"},
  setting={"frontlight","night_mode","network","screen","navigation","document","language","device"},
  network={"network_wifi","network_proxy","network_powersave","network_restore","network_info","network_before_wifi_action","network_after_wifi_action","ssh"},
  screen={"screensaver","autodim","screen_rotation","screen_dpi","screen_eink_opt","autowarmth"},
  navigation={"back_to_exit","back_in_filemanager","back_in_reader"},
  document={"document_metadata_location","document_auto_save","document_end_action"},
  device={"keyboard_layout","time","units","autosuspend","autoshutdown","screenshot"},
  tools={"read_timer","calibre","exporter","statistics","progress_sync","news_downloader","text_editor","profiles","more_tools"},
  more_tools={"battery_statistics","synchronize_time","keep_alive","terminal","plugin_management","patch_management"},
  search={"dictionary_lookup","wikipedia_lookup","file_search","find_book_in_calibre_catalog","opds","fulltext_search","bookmark_search"},
  reader={}, filemanager={},
  main={"history","favorites","collections","book_status","book_info","help","exit_menu"},
  help={"quickstart_guide","search_menu","report_bug","version","about"},
  exit_menu={"restart_koreader","sleep","exit"},
 }
 function menu:setUpdateItemTable()
  local i={["KOMenu:menu_buttons"]={}}
  for _,tab in ipairs(order["KOMenu:menu_buttons"]) do i[tab]={icon=tab} end
  for _,a in ipairs({"reader","filemanager"}) do if i[a] then i[a].callback=function() end; i[a].remember=false end end
  for _,c in ipairs({"network","screen","navigation","document","device","more_tools","help","exit_menu"}) do i[c]={text=c} end
  i.filemanager_display_mode={text=T("Display mode","Режим отображения"),sub_item_table=radio(ru and {"классический (только имена файлов)","мозаика с обложками","список с обложками и метаданными","список с метаданными, без изображений","список с обложками и именами файлов"} or {"classic (filename only)","mosaic with cover images","list with cover images and metadata","list with metadata, no images","list with cover images and filenames"},3)}
  i.filebrowser_settings={text=T("Settings","Настройки"),sub_item_table={check(T("Show hidden files","Показывать скрытые файлы"),false),
   {text=T("History settings","Настройки истории"),sub_item_table=sub("a")},{text=T("Home folder settings","Настройки домашней папки"),sub_item_table=sub("a")}}}
  i.show_filter={text=T("Book status: all","Статус книг: все"),sub_item_table=sub("a")}
  i.sort_by={text=T("Sort by: name","Сортировка: по имени"),sub_item_table=radio({"name","date"},1)}
  i.reverse_sorting=check(T("Reverse sorting","Обратная сортировка"),false)
  i.sort_mixed=check(T("Folders and files mixed","Папки и файлы вперемешку"),false)
  i.start_with={text=T("Start with: file browser","Начинать с: файлового менеджера"),sub_item_table=radio({"x"},1)}
  i.frontlight=act(T("Frontlight","Подсветка")); i.night_mode=check(T("Night mode","Ночной режим"),false)
  i.network_wifi=check(T("Wi-Fi connection","Подключение Wi-Fi"),true)
  i.network_proxy=check(T("HTTP proxy","HTTP-прокси"),false)
  i.network_powersave=check(T("Disable Wi-Fi connection when inactive","Отключать Wi-Fi при неактивности"),false)
  i.network_restore=check(T("Restore Wi-Fi connection on resume","Восстанавливать Wi-Fi после сна"),true)
  i.network_info=act(T("Network info","Сведения о сети"))
  i.network_before_wifi_action={text=T("Action when Wi-Fi is off","Действие при выключенном Wi-Fi"),sub_item_table=radio({T("turn on","включить"),T("prompt","спросить")},2)}
  i.network_after_wifi_action={text=T("Action when done with Wi-Fi","Действие после работы с Wi-Fi"),sub_item_table=radio({T("leave on","оставить"),T("turn off","выключить"),T("prompt","спросить")},2)}
  i.ssh={text=T("SSH server","SSH-сервер"),sub_item_table=sub("a")}
  i.screensaver={text=T("Sleep screen","Экран сна"),sub_item_table={{text=T("Wallpaper","Обои"),sub_item_table=sub("a")}}}
  i.autodim={text=T("Automatic dimmer","Автоматическое затемнение"),sub_item_table=sub("a")}
  i.screen_rotation={text=T("Rotation","Поворот"),sub_item_table=sub("a")}
  i.screen_dpi={text=T("Screen DPI","DPI экрана"),sub_item_table=radio({T("auto","авто"),T("custom","свой")},1)}
  i.screen_eink_opt={text=T("E-ink settings","Настройки E-ink"),sub_item_table={{text=T("Full refresh rate","Частота полного обновления"),sub_item_table=radio({T("every 6 pages","каждые 6 страниц")},1)},check(T("Flash buttons and menu items","Мигать кнопками и пунктами меню"),true)}}
  i.autowarmth={text=T("Auto warmth and night mode","Автотеплота и ночной режим"),sub_item_table=sub("a")}
  i.back_to_exit={text=T("Back to exit","«Назад» для выхода"),sub_item_table=radio({"x"},1)}
  i.back_in_filemanager={text=T("Back in file browser","«Назад» в файловом менеджере"),sub_item_table=radio({"x"},1)}
  i.back_in_reader={text=T("Back in reader","«Назад» при чтении"),sub_item_table=radio({"x"},1)}
  i.document_metadata_location={text=T("Book metadata location","Расположение метаданных"),sub_item_table=sub("a")}
  i.document_auto_save={text=T("Save book metadata","Сохранять метаданные"),sub_item_table=radio({"x"},1)}
  i.document_end_action={text=T("End of document action","Действие в конце документа"),sub_item_table={check(T("Always mark as finished","Всегда отмечать прочитанным"),false),
   radio({T("pop-up","спросить"),T("do nothing","ничего")},1)[1],radio({T("pop-up","спросить"),T("do nothing","ничего")},1)[2]}}
  i.language={text=T("Language","Язык"),sub_item_table=radio({"English","Русский"},ru and 2 or 1)}
  i.keyboard_layout={text=T("Keyboard","Клавиатура"),sub_item_table=sub("a")}
  i.time={text=T("Time and date","Дата и время"),sub_item_table={check(T("12-hour clock","12-часовой формат"),false)}}
  i.units={text=T("Dimension units","Единицы измерения"),sub_item_table=sub("a")}
  i.autosuspend={text=T("Autosuspend timeout: 15 min","Автоматический сон: 15 мин"),keep_menu_open=true,callback=function() end,sorting_hint="device"}
  i.autoshutdown={text=T("Autoshutdown timeout: 3 days","Автовыключение: 3 дн."),keep_menu_open=true,callback=function() end,sorting_hint="device"}
  i.screenshot={text=T("Screenshot folder","Папка снимков экрана"),callback=function() end}
  i.read_timer={text=T("Read timer","Таймер чтения"),sub_item_table=sub("a")}
  i.calibre={text="Calibre",sub_item_table=sub("a")}
  i.exporter={text=T("Export highlights","Экспорт выделений"),sub_item_table=sub("a")}
  i.statistics={text=T("Reading statistics","Статистика чтения"),sub_item_table=sub("a")}
  i.progress_sync={text=T("Progress sync","Синхронизация прогресса"),sub_item_table={act(T("Push progress from this device now","Отправить прогресс сейчас")),act(T("Pull progress from other devices now","Получить прогресс сейчас"))}}
  i.news_downloader={text=T("News downloader","Загрузчик новостей"),sub_item_table=sub("a")}
  i.text_editor={text=T("Text editor","Текстовый редактор"),sub_item_table=sub("a")}
  i.profiles={text=T("Profiles","Профили"),sub_item_table=sub("a")}
  i.battery_statistics=act(T("Battery statistics","Статистика батареи"))
  i.synchronize_time=act(T("Synchronize time","Синхронизировать время"))
  i.keep_alive=check(T("Keep alive","Не засыпать"),false)
  i.terminal={text=T("Terminal emulator","Эмулятор терминала"),sub_item_table=sub("a")}
  i.plugin_management={text=T("Plugin management","Управление плагинами"),sub_item_table=sub("a")}
  i.patch_management={text=T("Patch management","Управление патчами"),sub_item_table=sub("a")}
  i.dictionary_lookup=act(T("Dictionary lookup","Поиск в словаре")); i.wikipedia_lookup=act(T("Wikipedia lookup","Поиск в Википедии"))
  i.file_search=act(T("File search","Поиск файлов")); i.find_book_in_calibre_catalog=act(T("Calibre metadata search","Поиск по метаданным Calibre"))
  i.opds=act(T("OPDS catalog","Каталог OPDS")); i.fulltext_search=act(T("Fulltext search","Полнотекстовый поиск")); i.bookmark_search=act(T("Bookmark search","Поиск по закладкам"))
  i.history=act(T("History","История")); i.favorites=act(T("Favorites","Избранное")); i.collections=act(T("Collections","Коллекции"))
  i.book_status=act(T("Book status","Статус книги")); i.book_info=act(T("Book information","Информация о книге"))
  i.quickstart_guide=act(T("Quickstart guide","Краткое руководство")); i.search_menu=act(T("Menu search","Поиск по меню"))
  i.report_bug=act(T("Report a bug","Сообщить об ошибке")); i.version=act(T("Version","Версия")); i.about=act(T("About","О программе"))
  i.restart_koreader=act(T("Restart KOReader","Перезапустить KOReader")); i.sleep=act(T("Sleep","Сон")); i.exit=act(T("Exit","Выход"))
  i.table_of_contents=act(T("Table of contents","Оглавление")); i.bookmarks=act(T("Bookmarks","Закладки"))
  i.book_map=act(T("Book map","Карта книги")); i.page_browser=act(T("Page browser","Обзор страниц"))
  i.go_to=act(T("Go to page","Перейти на страницу")); i.skim_to=act(T("Skim document","Пролистать документ"))
  i.go_to_previous_location=act(T("Go back to previous location","Назад к предыдущему месту"))
  i.document_settings={text=T("Document settings","Настройки документа"),sub_item_table=sub("a")}
  self.plugin:addToMainMenu(i)
  self.tab_item_table=require("ui/menusorter"):mergeAndSort(nil,i,order)
 end
 return ui
end
''')
out = Path('dist')
cases = [(lang, v) for lang in ['en', 'ru'] for v in ['root', 'library', 'long', 'radio', 'book']] + [('en', 'library-landscape'), ('ru', 'root-landscape')]
for lang, name in cases:
        variant = name.split('-')[0]
        width, height = (1448, 1072) if name.endswith('landscape') else (1072, 1448)
        lua.globals().locale, lua.globals().variant = lang, variant
        lua.globals().preview_w, lua.globals().preview_h = width, height
        lua.execute('''
G_reader_settings.data={language=locale}; screen.night_mode=false; painted={}; screen.w=preview_w; screen.h=preview_h
local ui=previewUI(locale, variant=="book"); local p=Plugin:new{ui=ui}; ui.menu.plugin=p
ui.menu:onShowMenu(); local m=p.settings_menu
if variant=="library" then m:openTab("library")
elseif variant=="long" then m:openTab("network"); m:scrollTo(4*56)
elseif variant=="radio" then m:openItem("filemanager_display_mode"); m:onMenuSelect(m.item_table[1])
elseif variant=="book" then m:openTab("book") end
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
print('Wrote dist/menu-{root,library,long,radio,book}-{en,ru}.png, dist/menu-library-landscape-en.png and dist/menu-root-landscape-ru.png')
