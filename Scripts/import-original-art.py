"""Losslessly import baked AIR glyph/food pixels and Main.as glyph metrics.
Usage: python Scripts/import-original-art.py <ffdec image export> <Main.as>
No font rasterization, blur recreation or painted approximation is used.
"""
from pathlib import Path
import hashlib, json, re, sys
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
export, source = map(Path, sys.argv[1:])
text = source.read_text(encoding='utf-8')
values = list(map(float, re.search(r'_loc2_ = new <Number>\[([^\]]+)\]',
    text[text.index('internal function finishTextures'):]).group(1).split(',')))
rects = [values[i:i+7] for i in range(0, len(values), 7)]
assert len(rects) == 976
groups = {}
offset = 0
for sheet, count in [(0, 271), (1, 90), (3, 615)]:
    group = rects[offset:offset+count]; offset += count
    assert {int(r[0]) for r in group} == set(range(count))
    groups[sheet] = {int(r[0]): r[1:] for r in group}
metrics = list(map(float, re.search(r'_loc76_ = new <Number>\[([^\]]+)\]',
    text[text.index('this.chsz = 52;'):]).group(1).split(',')))
assert len(metrics) == 2852 and metrics[:2] == [52, 70.85]
atlas = Image.new('RGBA', (2048, 2048))
sheets = {s: Image.open(next(export.glob(f'*_sheet{s}_a_png.png'))).convert('RGBA') for s in [0, 3]}
cx = cy = 2; rowh = 0; imported = []

def put(sheet, id):
    global cx, cy, rowh
    x, y, w, h, ix, iy = map(int, groups[sheet][id])
    crop = sheets[sheet].crop((x+ix, y+iy, x+w-ix, y+h-iy))
    w, h = crop.size
    if cx + w + 2 > 2048: cx = 2; cy += rowh + 4; rowh = 0
    assert cy + h + 2 <= 2048
    atlas.paste(crop, (cx, cy))  # no mask: preserves straight RGBA bytes
    assert atlas.crop((cx, cy, cx+w, cy+h)).tobytes() == crop.tobytes()
    imported.append({'sheet': sheet, 'id': id, 'sha256': hashlib.sha256(crop.tobytes()).hexdigest()})
    result = [cx, cy, w, h]
    cx += w + 4; rowh = max(rowh, h)
    return result

glyphs = []
for bold in range(2):
    for char in range(95):
        for layer in range(3):
            seq = bold*285 + char*3 + layer
            rect = put(3, 569-seq)
            m = metrics[2+seq*5:7+seq*5]
            glyphs.append(rect + m)
foods = [put(0, 40-3*i) for i in range(10)]
shadow = put(0, 41)

def fmt(value):
    return f'{value:.6f}f'
header = '''/* Generated from original AIR baked sheets and Main.as; do not rasterize. */
#ifndef WYRM_ORIGINAL_ART_DATA_H
#define WYRM_ORIGINAL_ART_DATA_H
typedef struct { float x,y,w,h,px,py,scale,rw,advance; } original_glyph;
static const original_glyph ORIGINAL_GLYPHS[570] = {
'''
header += '\n'.join('  {' + ','.join(map(fmt,g)) + '},' for g in glyphs)
header += '\n};\nstatic const float ORIGINAL_FOOD_RECTS[11][4] = {\n'
header += '\n'.join('  {' + ','.join(map(fmt,g)) + '},' for g in foods+[shadow])
header += '\n};\n#endif\n'
for base in [ROOT.parent/'Wyrm Android', ROOT/'SharedEngine']:
    (base/'app/src/game/original_art_data.h').write_text(header, encoding='utf-8')
    atlas.save(base/'app/res/textures/original_art.png', optimize=True)
receipt = {'sourceSha256': hashlib.sha256(source.read_bytes()).hexdigest(), 'glyphs':570,
           'foodImages':11, 'pixelIdenticalCrops':len(imported), 'crops':imported}
(ROOT/'Scripts/original-art-receipt.json').write_text(json.dumps(receipt, indent=2)+'\n')
print(f'Imported {len(imported)} byte-identical crops; atlas used height {cy+rowh+2}')
