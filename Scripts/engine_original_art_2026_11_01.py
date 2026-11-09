"""Apply exact baked-art renderer edits to the prepared Apple tree."""
from pathlib import Path
import json
def apply(root):
    patches=json.loads((Path(__file__).with_name('engine_original_art_2026_11_01.json')).read_text())
    for file,pairs in patches.items():
        path=Path(root)/file
        text=path.read_text(encoding='utf-8')
        for old,new in pairs:
            if text.count(old)!=1:
                raise SystemExit(f'original art: {file}: {text.count(old)} anchors: {old[:70]!r}')
            text=text.replace(old,new,1)
        path.write_text(text,encoding='utf-8')
