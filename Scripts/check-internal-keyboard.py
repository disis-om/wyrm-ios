"""Check measured UIKit geometry, not just focus, in internal keyboard smokes."""
import re,sys
from pathlib import Path

def valid(text, composer=False):
 rows={}
 for kind,cw,ch,x,y,w,h,v in re.findall(r'Wyrm internal layout kind=(keys|composer) canvas=([\d.]+),([\d.]+) rect=([-\d.]+),([-\d.]+),([\d.]+),([\d.]+) visible=(0|1)',text):
  rows[kind]=tuple(map(float,[cw,ch,x,y,w,h,v]))
 def inside(row):
  cw,ch,x,y,w,h,v=row
  return cw>ch>0 and v==1 and w>0 and h>0 and x>=-1 and y>=-1 and x+w<=cw+1 and y+h<=ch+1
 keys=rows.get('keys')
 if not keys or not inside(keys) or keys[5]<150:return False
 if composer:
  field=rows.get('composer')
  return bool(field and inside(field) and field[3]+field[5]<=keys[3]+1)
 return True

if __name__=='__main__':
 if '--self-test' in sys.argv:
  base='Wyrm internal layout kind=keys canvas=874.0,402.0 rect=217.0,196.0,440.0,200.0 visible=1\n'
  field='Wyrm internal layout kind=composer canvas=874.0,402.0 rect=157.0,142.0,560.0,44.0 visible=1\n'
  assert valid(base) and valid(base+field,True)
  assert not valid(base.replace('196.0','258.0').replace('visible=1','visible=0'))
  assert not valid(base,True)
  assert not valid(base+field.replace('142.0','242.0'),True)
  assert not valid(base+'Wyrm internal layout kind=keys canvas=874.0,402.0 rect=217.0,258.0,440.0,200.0 visible=0\n')
  print('Internal keyboard measured bounds:6 fixtures passed')
 else:
  ok=valid(Path(sys.argv[1]).read_text(errors='replace'), '--composer' in sys.argv)
  print('Measured internal keyboard/composer visibility: '+('PASS' if ok else 'FAIL'))
  raise SystemExit(0 if ok else 1)
