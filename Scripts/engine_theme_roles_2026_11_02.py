"""Append hero roles to the existing arena palette ABI on both mobile apps."""
from pathlib import Path
import sys
PAIRS = {
 'app/src/game/arena_theme.h': [('  ARENA_THEME_ROLE_COUNT,', '''  ARENA_THEME_HERO,
  ARENA_THEME_ON_HERO,
  ARENA_THEME_HERO2,
  ARENA_THEME_ON_HERO2,
  ARENA_THEME_ROLE_COUNT,''')],
 'app/src/game/arena_theme.c': [('    0xFF2F6FDEu, 0xFFF0EEE9u, 0xFFEFEDE8u, 0xFFC4554Du,', '''    0xFF2F6FDEu, 0xFFF0EEE9u, 0xFFEFEDE8u, 0xFFC4554Du,
    0xFFDDC1A6u, 0xFF000000u, 0xFF000000u, 0xFFE5E5E5u,''')],
}
def apply(root,dry=False):
 for file,changes in PAIRS.items():
  p=Path(root)/file;t=p.read_text(encoding='utf-8')
  for before,after in changes:
   if after in t:
    if not dry:raise SystemExit('Theme roles already applied: '+file)
    assert t.count(after)==1
    t=t.replace(after,before,1)
   assert t.count(before)==1,(file,t.count(before))
   t=t.replace(before,after,1)
  if not dry:p.write_text(t,encoding='utf-8')
 print('Theme roles: 2 single anchors; dry='+str(dry))
if __name__=='__main__':apply(sys.argv[1],'--dry' in sys.argv)
