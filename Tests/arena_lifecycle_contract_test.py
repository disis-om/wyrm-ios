#!/usr/bin/env python3
"""Source-level contract checks for the Slither arena admission lifecycle."""

from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
subprocess.run([sys.executable, str(ROOT / "Scripts" / "prepare-original-engine.py")], cwd=ROOT, check=True)

services = (ROOT / "SourcesShell" / "WyrmServices.swift").read_text(encoding="utf-8")
design = (ROOT / "SourcesShell" / "WyrmDesignMain.swift").read_text(encoding="utf-8")
shell = (ROOT / "SourcesShell" / "WyrmShell.swift").read_text(encoding="utf-8")
generated = ROOT / "build-original-source" / "app" / "src"
game_data = (generated / "game" / "game_data.c").read_text(encoding="utf-8")
callback = (generated / "network" / "callback.c").read_text(encoding="utf-8")
home = (generated / "platform" / "android_home.c").read_text(encoding="utf-8")

checks = {
    "directory active flag": "bytes[offset] <= 26" in services,
    "active-count floor": "$0.active && $0.players > 20" in services,
    "ptc websocket endpoint": 'ws://\\(arena.address):80/ptc' in services,
    "binary p probe": "Data([112])" in services and "opcode: .binary" in services,
    "three rtt samples": "samples.count == 3" in services and "samples.min()" in services,
    "first-reply readiness": "addingTimeInterval(2.667)" in services,
    "directory fallback readiness": "addingTimeInterval(7)" in services,
    "weighted active-count choice": "arena.players + 5" in services,
    "two-minute taint": "seconds: Int = 120" in services,
    "automatic alternate retry": "failoverArena(refused:" in design and "engine.playOnline" in design,
    "native refusal bridge": "WyrmIOSArenaRefusalSnapshot" in shell and "WyrmIOSPublishArenaRefusal" in home,
    "short-life refusal classification": "refused_short_life" in callback and "arena_taint_mark" in callback,
    "no global 3333ms cooldown": "last_connect_ms + min_interval_ms" not in game_data,
}

failed = [name for name, passed in checks.items() if not passed]
for name, passed in checks.items():
    print(f"{'PASS' if passed else 'FAIL'}: {name}")
if failed:
    raise SystemExit("arena lifecycle contract failed: " + ", ".join(failed))
print(f"PASS: {len(checks)}/{len(checks)} arena lifecycle source contracts")
