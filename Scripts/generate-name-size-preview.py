"""Bake the settings preview label from the shipped thin glyph layers."""
from pathlib import Path
import hashlib
import json
import re
from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
ANDROID = ROOT / 'Wyrm Android'
SHARED = ROOT / 'Wyrm iOS/SharedEngine'
source = (ANDROID / 'app/src/game/original_art_data.h').read_text()
rows = [list(map(float, x.replace('f', '').split(',')))
        for x in re.findall(r'\{([\d.,f-]+)\}', source)][:570]
atlas = Image.open(ANDROID / 'app/res/textures/original_art.png').convert('RGBA')
canvas = Image.new('RGBA', (600, 150))
for layer in [1, 0]:
    pen = 30.0
    for character in 'wyrmplayer':
        index = 285 + (ord(character)-32)*3
        x,y,w,h,px,py,scale,_,_ = rows[index+layer]
        crop = atlas.crop((int(x), int(y), int(x+w), int(y+h)))
        if layer == 1:
            crop.putalpha(crop.getchannel('A').point(lambda a: round(a*.75)))
        canvas.alpha_composite(crop, (round(pen-px*scale), round(15-py*scale)))
        pen += rows[index][8]
preview = canvas.crop(canvas.getbbox())
asset = 'app/res/textures/name_size_preview.png'
for tree in [ANDROID, SHARED]:
    preview.save(tree / asset)
manifest = SHARED / 'SHA256.json'
pins = json.loads(manifest.read_text())
pins[asset] = hashlib.sha256((SHARED / asset).read_bytes()).hexdigest()
manifest.write_text(json.dumps(pins, indent=2)+'\n')
print('Preview label:', preview.size, pins[asset])
