"""Run with Python + lupa (pip install lupa); no WoW or saved data required."""
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / '.test-deps'))
from lupa.lua51 import LuaRuntime

lua = LuaRuntime(unpack_returned_tuples=True)
for path in ROOT.rglob('*.lua'):
    if '.test-deps' not in path.parts:
        lua.execute('assert(loadstring(...))', path.read_text(encoding='utf-8-sig'))
print('All addon files compile as Lua 5.1')

source = (ROOT / 'AccountPlayed.lua').read_text(encoding='utf-8-sig')
def block(start, end):
    return source[source.index(start):source.index(end)]

lua.execute('''
RAID_CLASS_COLORS = { MAGE = { r = 0.2, g = 0.6, b = 1 } }
AccountPlayed = { popupRows = {}, pieSlices = {} }
''')
lua.execute(block('local RACE_PALETTE', 'local function GetGroupLabel') + '''
for _, race in ipairs({'Human', 'Orc', 'NightElf', 'UNKNOWN'}) do
    local first = GetGroupColor('race', race, 1)
    local changed = GetGroupColor('race', race, 9)
    assert(first.r == changed.r and first.g == changed.g and first.b == changed.b)
end
''')
lua.execute(block('local function GetPositiveAngle', 'local function GetPieEntryAtCursor') + '''
local zero, first, second = {pieShare=0}, {pieShare=0.25}, {pieShare=0.75}
local entries = {zero, first, second}
assert(GetEntryAtPieRatio(entries, 0) == first)
assert(GetEntryAtPieRatio(entries, 0.249) == first)
assert(GetEntryAtPieRatio(entries, 0.25) == second)
assert(GetEntryAtPieRatio(entries, 0.999) == second)
assert(GetEntryAtPieRatio({}, 0) == nil)
for _, point in ipairs({{1,0,0},{0,1,0.25},{-1,0,0.5},{0,-1,0.75}}) do
    assert(math.abs(GetPositiveAngle(point[1], point[2]) / (math.pi*2) - point[3]) < 0.00001)
end
''')
lua.execute('local AP = AccountPlayed\n' + block('local function HighlightPieEntry', 'local function CreateDistributionRow') + '''
FormatTimeTotal = function() return '100h' end
-- The helper captures the global formatter in this isolated test.
local a, b = {}, {}
local s1, s2 = {entry=a}, {entry=b}
function s1:SetAlpha(v) assert(type(v)=='number'); self.alpha=v end
s2.SetAlpha = s1.SetAlpha
AP.pieSlices = {s1, s2}
local text = {SetText=function() end, SetTextColor=function() end}
local frame = {pieEntries={a,b}, pieAccountTotal=360000, pieFrame={centerText=text}}
AccountPlayedPopupDB = {}
HighlightPieEntry(frame, nil)
assert(s1.alpha == 1 and s2.alpha == 1)
''')
print('Stable colors, zero shares, slice boundaries, cursor quadrants and hover reset pass')
