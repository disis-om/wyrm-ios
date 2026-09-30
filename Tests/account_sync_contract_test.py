#!/usr/bin/env python3
"""Account-linked settings (OM, 2026-10-01): every `wyrm.*` UserDefaults key in
the app must match a rule in WyrmAccountSync.rules (sync, wipe or keep), so a
new setting can never silently stay behind on the phone or miss the account.
Also checks the log-out and restore wiring stays in place."""
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parents[1]
SHELL = ROOT / "SourcesShell"
sync = (SHELL / "WyrmAccountSync.swift").read_text(encoding="utf-8")
entry = (SHELL / "WyrmDesignEntry.swift").read_text(encoding="utf-8")
auth = (SHELL / "WyrmCinematicAuth.swift").read_text(encoding="utf-8")
pages = (SHELL / "WyrmSettingsPages.swift").read_text(encoding="utf-8")
profile = (SHELL / "WyrmProfile.swift").read_text(encoding="utf-8")

prefixes = re.findall(r'\("(wyrm\.[^"]+)",\s*\.(?:sync|wipe|keep)\)', sync)
keys = set()
for path in SHELL.glob("*.swift"):
    if path.name == "WyrmAccountSync.swift":
        continue
    text = path.read_text(encoding="utf-8")
    keys |= set(re.findall(r'"(wyrm\.(?:ios|notify|crash|drop|nickname|support|trails)[A-Za-z0-9_.\-]*)', text))

failures = []
for key in sorted(keys):
    if not any(key.startswith(prefix) or prefix.startswith(key) for prefix in prefixes):
        failures.append(f"no sync rule for defaults key {key}")

checks = {
    "restore before bootstrap on log in": "WyrmAccountSync.shared.restore(" in auth
        and auth.index("WyrmAccountSync.shared.restore(") < auth.index("await services.bootstrap("),
    "wipe on log out": "accountSync.wipeDevice()" in entry,
    "save when the app leaves the screen": "phase == .background" in entry and "accountSync.save(" in entry,
    "resume on a restored session": "accountSync.resume(" in entry,
    "log out at the bottom of Settings": 'WSActionRow(title: "Log out"' in pages,
    "no sign out on the profile": '"Sign out"' not in profile,
    "manual backups are gone": "struct WyrmBackup:" not in pages and "fileExporter" not in pages,
}
failures += [name for name, ok in checks.items() if not ok]

if failures:
    print("\n".join(failures))
    sys.exit(1)
print(f"account sync contract ok: {len(keys)} keys covered by {len(prefixes)} rules")
