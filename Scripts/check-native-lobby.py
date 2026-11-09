"""Require native scene/content and SDL drawable landscape evidence together."""
from pathlib import Path
import re
import sys


def native_lobby_ready(text):
    native = any(int(w) > int(h) > 0 and int(cw) > int(ch) > 0
                 for w, h, cw, ch in re.findall(
                     r'Wyrm native orientation=game-landscape bounds=(\d+)x(\d+) content=(\d+)x(\d+)', text))
    drawable = any(int(w) > int(h) > 0 for w, h in re.findall(r'drawable=(\d+)x(\d+)', text))
    return native and drawable and 'screen=LOBBY' in text


if __name__ == '__main__':
    path = Path(sys.argv[1])
    ok = native_lobby_ready(path.read_text(encoding='utf-8', errors='replace') if path.is_file() else '')
    if '--quiet' not in sys.argv:
        print('Native lobby scene/content/drawable landscape: ' + ('PASS' if ok else 'NOT READY'))
    raise SystemExit(0 if ok else 1)
