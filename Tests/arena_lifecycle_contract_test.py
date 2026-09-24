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
loop = (generated / "game" / "loop.c").read_text(encoding="utf-8")
server = (generated / "network" / "server.c").read_text(encoding="utf-8")
callback = (generated / "network" / "callback.c").read_text(encoding="utf-8")
home = (generated / "platform" / "android_home.c").read_text(encoding="utf-8")

checks = {
    "directory active flag": "bytes[offset] <= 26" in services,
    "direct game-port TCP latency probe": "NWConnection(host: NWEndpoint.Host(arena.address), port: port, using: .tcp)" in services,
    "probe reports connect milliseconds": "DispatchTime.now().uptimeNanoseconds - probeStarted" in services and "elapsed / 1_000_000" in services,
    "bounded probe timeout": "queue.asyncAfter(deadline: .now() + 1.5)" in services,
    "directory refresh avoids fleet-wide game-port probes": "func refreshArenasLive() async" in services and "for arena in candidates { group.addTask" not in services,
    "picker measures at most ten on demand": "func measurePickerArenas(preferredEndpoints:" in services and ".prefix(10)" in services and "await services.measurePickerArenas" in design,
    "picker shows only active directory arenas": r"services.arenas.filter(\.active)" in design,
    "picker ranks top ten and can expand": "Array(ranked.prefix(10))" in design and "See all" in design,
    "custom addresses are validated and stored": "static func custom(_ raw: String)" in services and "savedArenaEndpoints = entries.prefix(20)" in design,
    "recent joins are kept separately from saved addresses": "recentArenaEndpoints = recent.prefix(5)" in design,
    "lowest measured latency is recommended": "if left != right { return left < right }" in services,
    "explicit choice overrides automatic recommendation": "if userSelectedArena" in design and "return services.recommendedArena" in design,
    "two-second directory-only picker refresh": "Task.sleep(nanoseconds: 2_000_000_000)" in design,
    "no Swift alternate-server failover": "failoverArena(refused:" not in design and "engine.playOnline" not in design,
    "native refusal bridge": "WyrmIOSArenaRefusalSnapshot" in shell and "WyrmIOSPublishArenaRefusal" in home,
    "short silent life returns to lobby": "refused_short_life" in callback and "gdata->join_spawned = false" in callback and "gdata->curr_screen = LOBBY" in loop,
    "no death card before own spawn": "if (!refused_short_life && gdata->join_spawned)" in callback,
    "Vlither five-second entry timeout": "SDL_GetTicks() - gdata->attempt_started_ms > 5000" in loop and "if (gdata->connection &&" in loop,
    "one dial per Play request": "ios_retry_or_finish" not in loop and "gdata->rejoin_at_ms = SDL_GetTicks() + 50" not in loop and "gdata->join_attempts++" not in server,
    "failure is reported without alternate attempt": "android_home_arena_refused(usrs->ipv4, 0)" in loop and "failoverArena(refused:" not in design,
    "manual join respects previous socket close": "last_connect_ms + min_interval_ms" in game_data and "gdata->rejoin_at_ms = due" in game_data,
    "socket failures report their actual phase": all(phrase in callback for phrase in (
        "TCP connected", "WebSocket upgraded", "WebSocket close frame",
        "socket closed in phase", "after challenge, before configuration",
        "after configuration, before spawn", "after spawn")),
    "join diagnostics omit secret and nickname values": "join fields accessory=" in callback and "nickname_bytes=%d" in callback,
}

failed = [name for name, passed in checks.items() if not passed]
for name, passed in checks.items():
    print(f"{'PASS' if passed else 'FAIL'}: {name}")
if failed:
    raise SystemExit("arena lifecycle contract failed: " + ", ".join(failed))
print(f"PASS: {len(checks)}/{len(checks)} arena lifecycle source contracts")
