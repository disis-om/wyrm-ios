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
    "direct game-port TCP latency probe": "NWConnection(host: NWEndpoint.Host(arena.address), port: port, using: .tcp)" in services,
    "probe reports connect milliseconds": "DispatchTime.now().uptimeNanoseconds - probeStarted" in services and "elapsed / 1_000_000" in services,
    "bounded probe timeout": "queue.asyncAfter(deadline: .now() + 1.5)" in services,
    "all active arenas are measured": r"arenas.filter(\.active)" in services and "arenaLatencies[id] = value ?? -1" in services,
    "lowest measured latency is recommended": "if left != right { return left < right }" in services,
    "explicit choice overrides automatic recommendation": "if userSelectedArena" in design and "return services.recommendedArena" in design,
    "two-second picker refresh": "Task.sleep(nanoseconds: 2_000_000_000)" in design,
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
