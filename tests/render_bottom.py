"""Preview actual drawer paint calls using Arial metrics and resvg (not KOReader UI)."""
import base64
from html import escape
from pathlib import Path
import runpy
from PIL import ImageFont, Image, ImageOps
from io import BytesIO
import resvg_py
lua = runpy.run_path('tests/bottom.py')['lua']
font_dir = Path('/System/Library/Fonts/Supplemental')
def measure(text, size, bold):
    return ImageFont.truetype(str(font_dir / ('Arial Bold.ttf' if bold else 'Arial.ttf')), round(size)).getlength(text)
lua.globals().measure = measure
def wrap_text(text, width, size):
    lines=[]
    for paragraph in text.split('\n'):
        line=''
        for word in paragraph.split():
            if line and measure(line+' '+word,size,False)>width:
                lines.append(line);line=word
            else: line=(line+' '+word).strip()
        lines.append(line)
    return lua.table_from(lines)
lua.globals().wrap_text=wrap_text
lua.execute('''
local Text=require("ui/widget/textwidget")
function Text:getSize() return {w=math.min(self.max_width or math.huge,measure(self.text,self.face,self.bold)),h=self.face} end
screen.w=1072; screen.h=1448; screen.dpi_scale=2
power.intensity=12; power.warmth=50; device.frontlight=true; device.warm=true; device.wifi=true
''')
lua.execute(r'''
local TextBox=require("ui/widget/textboxwidget")
function TextBox:getAllLineCount() self.lines=wrap_text(self.text,self.width,self.face); return #self.lines end
function TextBox:paintTo(bb,x,y)
 self:getAllLineCount()
 local count=self:getVisLineCount()
 local start=math.floor((self.ratio or 0)*math.max(0,#self.lines-count))+1
 for i=start,math.min(#self.lines,start+count-1) do
  painted[#painted+1]={kind="text",text=self.lines[i],x=x,y=y+(i-start)*self.face*1.3,size=self.face}
 end
end
local Icon=require("ui/widget/iconwidget")
function Icon:paintTo(bb,x,y)
 painted[#painted+1]={kind="image",file=koreader_root.."/resources/icons/mdlight/"..self.icon..".svg",x=x,y=y,w=self.width,h=self.height}
end
function Icon:free() end
local Text=require("ui/widget/textwidget")
function Text:paintTo(bb,x,y)
 local text=self.text
 while measure(text,self.face,self.bold)>self.max_width and #text>0 do
  text=text:sub(1,-2)
 end
 painted[#painted+1]={kind="text",text=text,x=x,y=y,size=self.face,bold=self.bold}
end
''')
for variant in ['book', 'book-landscape', 'editor', 'number', 'help', 'confirm', 'editor-landscape', 'font', 'layout', 'page', 'more', 'font-dark', 'more-dark', 'choice', 'choice-dark', 'layout-landscape']:
    lua.globals().night = variant.endswith('-dark')
    lua.globals().tab_index = ['font','layout','page','more'].index(variant.split('-')[0])+1 if variant.split('-')[0] in ['font','layout','page','more'] else 2
    lua.globals().inline_preview = variant.split('-')[0]
    lua.globals().choice_preview = variant.startswith('choice')
    width,height = (1448,1072) if variant.endswith('landscape') else (1072,1448)
    lua.globals().preview_w, lua.globals().preview_h = width,height
    lua.execute('''
G_reader_settings.data={language="en",night_mode=night}; screen.night_mode=night; painted={}
screen.w=preview_w; screen.h=preview_h
local p=Plugin:new{ui=makeReader(cre)}; p:onKindleBottomDrawer(); p.bottom_drawer:selectTab(tab_index)
if choice_preview then p.bottom_drawer:showChoices(p.bottom_drawer:findOptionByName("block_rendering_mode")) end
local d=p.bottom_drawer
if inline_preview=="book" then
 function p.ui:getCurrentPage() return 369 end
 function p.ui.document:getPageCount() return 810 end
 p.ui.doc_props={display_title="The River — Chapter One"}
 p:onQuickActionsPanel(); d=p.quick_actions_panel
end
if inline_preview=="editor" or inline_preview=="number" or inline_preview=="confirm" then
 d:more(d:findOptionByName("h_page_margins"))
 if inline_preview=="number" then d:editField(d.inline_panel.fields[1]) end
 if inline_preview=="confirm" then d:saveEditorDefault(d.inline_panel) end
elseif inline_preview=="help" then d:showHelp(d:findOptionByName("font_fine_tune")) end
d:paintTo(bb)
''')
    parts=[f'<svg xmlns="http://www.w3.org/2000/svg" width="{width}" height="{height}"><rect width="{width}" height="{height}" fill="#eee"/>']
    ink = 'white' if variant.endswith('-dark') else 'black'
    parts.append(f'<defs><pattern id="shade" width="6" height="6" patternUnits="userSpaceOnUse"><rect width="3" height="3" fill="{ink}"/><rect x="3" y="3" width="3" height="3" fill="{ink}"/></pattern></defs>')
    for item in lua.globals().painted.values():
        x,y=item['x'],item['y']
        if item['kind']=='rect':
            parts.append(f'<rect x="{x}" y="{y}" width="{item["w"]}" height="{item["h"]}" fill="{item["color"]}"/>')
        elif item['kind']=='text':
            parts.append(f'<text x="{x}" y="{y+item["size"]}" font-family="Arial" font-size="{item["size"]}" font-weight="{700 if item["bold"] else 400}">{escape(item["text"])}</text>')
        elif item['kind']=='shade':
            parts.append(f'<rect x="{x}" y="{y}" width="{item["w"]}" height="{item["h"]}" fill="url(#shade)"/>')
        else:
            data=base64.b64encode(Path(item['file']).read_bytes()).decode()
            parts.append(f'<image x="{x}" y="{y}" width="{item["w"]}" height="{item["h"]}" href="data:image/svg+xml;base64,{data}"/>')
    parts.append('</svg>')
    svg=''.join(parts)
    Path(f'dist/bottom-{variant}.svg').write_text(svg)
    png = resvg_py.svg_to_bytes(svg_string=svg)
    # Simulate the global screen inversion KOReader applies after UI painting.
    if variant.endswith('-dark'):
        output = BytesIO()
        ImageOps.invert(Image.open(BytesIO(png)).convert('RGB')).save(output, format='PNG')
        png = output.getvalue()
    Path(f'dist/bottom-{variant}.png').write_bytes(png)
