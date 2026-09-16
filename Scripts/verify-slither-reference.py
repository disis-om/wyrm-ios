"""Read-only comparison with the owner-provided Slither web reference."""
import hashlib
import re
import sys
from pathlib import Path

root = Path(__file__).resolve().parent.parent
reference = Path(sys.argv[1])
raw = reference.read_bytes()
js = re.sub(r'\s+', '', raw.decode('utf-8-sig'))
protocol = (root / 'SharedEngine/app/src/network/arena_protocol.h').read_text()
checks = {
    'aim': ('last_e_mtm>33', 'ARENA_AIM_MS', 33),
    'turn': ('lkstm>50', 'ARENA_TURN_MS', 50),
    'boost': ('last_accel_mtm>50', 'ARENA_BOOST_MS', 50),
    'ping': ('last_ping_mtm>250', 'ARENA_PING_MS', 250),
    'lag': ('last_ping_mtm>750', 'ARENA_LAG_MS', 750),
    'retry': ('start_connect_mtm>3333', 'ARENA_RETRY_MS', 3333),
    'death': ('dead_mtm>1600', 'ARENA_DEATH_WAIT_MS', 1600),
}
for name, (needle, constant, expected) in checks.items():
    assert needle in js, f'Reference missing {name}'
    assert re.search(r'\b' + constant + r'\s*=\s*' + str(expected) + r'\b', protocol), name
    print(f'PASS {name}: {expected} ms')
for needle in ('if(!wfpr)if(ctm-last_ping_mtm>250)', 'ba[0]=251',
               'ba[0]=253', 'ba[0]=254', 'login_fr-=.004*vfr',
               'if(ws!=this)return', 'client_version=291'):
    assert needle in js, f'Reference changed: {needle}'
fingerprint = re.search(r'varcpw=\[([^]]+)\]', js).group(1)
persona = re.sub(r'\s+', '', (root / 'SharedEngine/app/src/network/arena_persona.c').read_text())
assert fingerprint in persona, 'Web fingerprint differs'
print('PASS web version 291, fingerprint and reference timing predicates')
print('Reference SHA256:', hashlib.sha256(raw).hexdigest())
print('Scope: source comparison; not full packet replay or live arena acceptance.')
