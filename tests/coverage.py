"""Coverage of the new menu layout against real KOReader sources.

usage: tests/coverage.py KOREADER_ROOT [MORE_ROOTS...]

For every root: every id in frontend/ui/elements/*_menu_order.lua and every menu key
that frontend code or a plugin's addToMainMenu defines is fed, with its real
sorting_hint, through KOReader's own MenuSorter (from the first root) and the
plugin's sort guard and layout. Prints how each key was placed and fails if any key
falls to the safety net or lands in Other plugins without a rule.
"""
import re
import sys
from pathlib import Path
from lupa.lua51 import LuaRuntime

roots = [Path(p) for p in sys.argv[1:]] or [Path('/tmp/koreader-src/koreader')]
sorter_root = roots[0]

KEY = re.compile(r'\b(?:menu_items|common_settings|common_info|exit_settings)\s*(?:\.\s*([A-Za-z_][A-Za-z0-9_]*)|\[\s*"([^"]+)"\s*\])\s*=[^=]')
HINT = re.compile(r'sorting_hint\s*=\s*\(?\s*"([^"]+)"')


def defined_keys(path):
    """Menu keys assigned in a Lua file, with the first sorting_hint before the next assignment."""
    text = path.read_text(errors='replace')
    text = re.sub(r'--\[\[.*?\]\]', '', text, flags=re.S)  # drop block comments
    text = '\n'.join(line.split('--', 1)[0] if not line.lstrip().startswith('--[[') else '' for line in text.split('\n'))
    found = list(KEY.finditer(text))
    out = {}
    for i, m in enumerate(found):
        key = m.group(1) or m.group(2)
        if key in ('sub_item_table', 'id', 'text', 'callback') or ':' in key:
            continue
        end = found[i + 1].start() if i + 1 < len(found) else len(text)
        hint = HINT.search(text, m.end(), end)
        if key not in out or (hint and not out[key]):
            out[key] = hint.group(1) if hint else None
    return out


def order_ids(path):
    text = re.sub(r'"-{3,}"', '', path.read_text())  # separators, which contain "--"
    text = '\n'.join(line.split('--', 1)[0] for line in text.split('\n'))
    ids = set(re.findall(r'"([^"]+)"', text))
    ids |= set(re.findall(r'^\s{4}([a-z_]+)\s*=\s*\{', text, flags=re.M))
    return {i for i in ids if not i.startswith('-') and not i.startswith('KOMenu')}


# readerui.lua registers these modules only for reflowable (CRE) documents.
ROLLING_ONLY = ('readerfont.lua', 'readertypeset.lua', 'readerstyletweak.lua', 'readertypography.lua')
# FileManagerBookInfo registers its menu item only in the reader (filemanagerbookinfo.lua init).
READER_ONLY = ('filemanagerbookinfo.lua',)

lua = LuaRuntime(unpack_returned_tuples=True)
lua.globals().sorter_path = str(sorter_root / 'frontend/ui/menusorter.lua')
lua.execute(r'''
package.path = "kindle-drawer.koplugin/?.lua;" .. package.path
log_lines = {}
local function rec(level) return function(...) local t={level}; for _,v in ipairs({...}) do t[#t+1]=tostring(v) end; log_lines[#log_lines+1]=table.concat(t," ") end end
package.preload["logger"] = function() return {dbg=function() end, info=rec("info"), warn=rec("warn"), err=rec("err")} end
package.preload["gettext"] = function() return setmetatable({}, {__call=function(_, s) return s end}) end
package.preload["datastorage"] = function() return {getSettingsDir=function() return "/nonexistent" end} end
package.preload["libs/libkoreader-lfs"] = function() return {attributes=function() return nil end} end
package.preload["ffi/util"] = function() return {orderedPairs=function(t)
  local keys={} for k in pairs(t) do keys[#keys+1]=k end
  table.sort(keys, function(a,b) return tostring(a)<tostring(b) end)
  local i=0
  return function() i=i+1; local k=keys[i]; if k~=nil then return k, t[k] end end
end} end
package.preload["ffi/utf8proc"] = function() return {} end
package.preload["ui/uimanager"] = function() return {} end
package.preload["device"] = function() return {hasExitOptions=function() return true end} end
G_reader_settings = {readSetting=function(_, _, d) return d end}
package.preload["ui/menusorter"] = function() return dofile(sorter_path) end
Layout = require("layout")
Layout.installSortGuard()
MenuSorter = require("ui/menusorter")
function run(order_path, keys, hints, reader, kind)
  local order = dofile(order_path)
  local items = {["KOMenu:menu_buttons"] = {}}
  for _, key in ipairs(keys) do
    if key == "zz_synthetic_textfunc" then items[key] = {text_func = function() return key end, callback = function() end}
    elseif order[key] then items[key] = {text = key}
    else items[key] = {text = key, sorting_hint = hints[key], sub_item_table = {{text = key .. " child"}}} end
  end
  for _, tab in ipairs(order["KOMenu:menu_buttons"]) do items[tab] = items[tab] or {text = tab}; items[tab].text = nil; items[tab].icon = tab end
  local tree = MenuSorter:mergeAndSort(nil, items, order)
  local layout = Layout.build{tree = tree, snapshot = Layout.snapshotFor(tree), reader = reader, kind = kind, drawer = true, report = true}
  local snap = Layout.snapshotFor(tree)
  return layout.report, layout.placements, snap.items
end
''')
run = lua.globals().run
known = set(lua.eval('Layout.knownIds()').keys())
failures = []
for root in roots:
    plugin_keys, plugin_hints, doc_only = {}, {}, set()
    for main in sorted((root / 'plugins').glob('*.koplugin/*.lua')):
        if 'kindle-drawer' in str(main):
            continue
        keys = defined_keys(main)
        plugin_keys.update(keys)
        if main.name == 'main.lua' and re.search(r'is_doc_only\s*=\s*true', main.read_text(errors='replace')):
            doc_only |= set(keys)
    for key, hint in plugin_keys.items():
        if hint:
            plugin_hints[key] = hint
    core = {'reader': {}, 'filemanager': {}, 'both': {}}
    rolling_only = set()
    for lua_file in sorted((root / 'frontend').rglob('*.lua')):
        rel = str(lua_file.relative_to(root))
        where = 'reader' if '/apps/reader/' in rel or rel.endswith(READER_ONLY) else 'filemanager' if '/apps/filemanager/' in rel else 'both'
        for key, hint in defined_keys(lua_file).items():
            core[where][key] = hint
            if rel.endswith(ROLLING_ONLY):
                rolling_only.add(key)
    # Our own plugin's key comes from this checkout.
    plugin_keys['kindle_drawer'] = 'more_tools'
    plugin_hints['kindle_drawer'] = 'more_tools'
    print(f'== {root}')
    for name, reader, kinds in (('filemanager', False, ['rolling']), ('reader', True, ['rolling', 'paging'])):
        order_path = root / f'frontend/ui/elements/{name}_menu_order.lua'
        ids = order_ids(order_path)
        hints = dict(plugin_hints)
        keys = set(ids) | set(core['both']) | set(core[name])
        for k, h in list(core['both'].items()) + list(core[name].items()):
            if h:
                hints[k] = h
        keys |= {k for k in plugin_keys if reader or k not in doc_only}
        # Two synthetic plugins through the real MenuSorter: a bogus hint (crashes stock KOReader)
        # and an item with only text_func.
        keys |= {'zz_synthetic_bogus_hint', 'zz_synthetic_textfunc'}
        hints['zz_synthetic_bogus_hint'] = 'no_such_menu'

        for kind in kinds:
            kind_keys = keys - rolling_only if kind == 'paging' else keys
            report, placements, snap_items = run(str(order_path), lua.table_from(sorted(kind_keys)), lua.table_from(hints), reader, kind)
            routed = dict(report['routed'].items())
            net = list(report['net'].values())
            dissolved = set(report['dissolved'].values())
            inside = set(report['inside'].values())
            placed = {k for k in placements.keys()}
            in_snapshot = set(snap_items.keys())
            no_rule = sorted(k for k, t in routed.items() if t == 'other' and not hints.get(k) and not k.startswith('zz_synthetic'))
            assert routed.get('zz_synthetic_bogus_hint') == 'other' and routed.get('zz_synthetic_textfunc') == 'other', routed
            by_rule = sorted(f'{k}→{t}' for k, t in routed.items() if k not in no_rule)
            print(f'-- {name} {kind}: {len(in_snapshot)} keys, {len(placed - inside)} placed by the layout, '
                  f'{len(inside)} inside a kept submenu, {len(dissolved)} dissolved containers')
            print(f'   inside kept submenus: {", ".join(sorted(inside)) or "none"}')
            print(f'   routed by hint rule: {", ".join(by_rule) or "none"}')
            print(f'   no rule, Other plugins: {", ".join(no_rule) or "none"}')
            print(f'   safety net: {", ".join(sorted(net)) or "none"}')
            if net:
                failures.append(f'{root} {name} {kind}: safety net {net}')
            if no_rule:
                failures.append(f'{root} {name} {kind}: no rule for {no_rule}')
if failures:
    print('FAIL:')
    for f in failures:
        print(' ', f)
    sys.exit(1)
print('PASS: every order id and menu key is placed by the layout or routed by a rule; '
      'synthetic bogus-hint and text_func-only plugins land in Other plugins through the real MenuSorter')
