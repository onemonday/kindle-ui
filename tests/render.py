"""Preview actual drawer paint calls using Arial metrics and resvg (not KOReader UI)."""
import base64
from html import escape
from pathlib import Path
import runpy
from PIL import ImageFont, Image, ImageOps
from io import BytesIO
import resvg_py
lua = runpy.run_path('tests/run.py')['lua']
font_dir = Path('/System/Library/Fonts/Supplemental')
def measure(text, size, bold):
    return ImageFont.truetype(str(font_dir / ('Arial Bold.ttf' if bold else 'Arial.ttf')), round(size)).getlength(text)
lua.globals().measure = measure
lua.execute('''
local Text=require("ui/widget/textwidget")
function Text:getSize() return {w=math.min(self.max_width,measure(self.text,self.face,self.bold)),h=self.face} end
screen.w=1072; screen.h=1448; screen.dpi_scale=2
power.intensity=12; power.warmth=50; device.frontlight=true; device.warm=true; device.wifi=true
''')
for variant in ['en', 'ru', 'en-dark', 'ru-dark']:
    lang = variant[:2]
    lua.globals().night = variant.endswith('-dark')
    lua.globals().locale = lang
    lua.execute('''
G_reader_settings.data={language=locale,night_mode=night}; screen.night_mode=night; network.on=true; painted={}
local p=Plugin:new{ui=newUI()}; p:onKindleDrawer(); p.drawer:paintTo(bb)
''')
    parts=['<svg xmlns="http://www.w3.org/2000/svg" width="1072" height="1448"><rect width="1072" height="1448" fill="#eee"/>']
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
    Path(f'dist/preview-{variant}.svg').write_text(svg)
    png = resvg_py.svg_to_bytes(svg_string=svg)
    # Simulate the global screen inversion KOReader applies after UI painting.
    if variant.endswith('-dark'):
        output = BytesIO()
        ImageOps.invert(Image.open(BytesIO(png)).convert('RGB')).save(output, format='PNG')
        png = output.getvalue()
    Path(f'dist/preview-{variant}.png').write_bytes(png)
