"""Run upstream ImageWidget.paintTo against a recording framebuffer double.

Usage: python tests/nightmode.py /path/to/koreader
Checks the real upstream draw pipeline, without a physical display or SVG decoder.
"""
from pathlib import Path
import sys
from lupa.lua51 import LuaRuntime
source = (Path(sys.argv[1]) / 'frontend/ui/widget/imagewidget.lua').read_text()
start = source.index('function ImageWidget:paintTo(bb, x, y)')
end = source.index('\n-- This will normally', start)
lua = LuaRuntime()
lua.execute('''
ImageWidget={}; Screen={night_mode=true}; logger={dbg=function() end}
Blitbuffer={TYPE_BB8A=1,TYPE_BBRGB32=2}
Geom={new=function(_,v) return v end}
''')
lua.execute(source[start:end])
lua.execute('''
local inversions,blends=0,0
local bb={invertRect=function() inversions=inversions+1 end,
 alphablitFrom=function() blends=blends+1 end,
 pmulalphablitFrom=function() blends=blends+1 end}
local widget=setmetatable({alpha=true,original_in_nightmode=false,
 _bb={getType=function() return 2 end},_offset_x=0,_offset_y=0,
 getSize=function() return {w=62,h=62} end}, {__index=ImageWidget})
for _,night in ipairs({false,true,false}) do
 Screen.night_mode=night
 for _,straight in ipairs({false,true}) do
  widget._is_straight_alpha=straight; widget:paintTo(bb,0,0)
 end
end
assert(blends==6 and inversions==0, "UI SVG must alpha blend without rectangle inversion")
-- Reproduce the previous defect using ImageWidget's default option.
widget.original_in_nightmode=true; Screen.night_mode=true; widget:paintTo(bb,0,0)
assert(inversions==1, "old settings should reproduce night-mode rectangle inversion")
''')
print('PASS: upstream ImageWidget pipeline in both themes and both alpha formats; old defect reproduced')
