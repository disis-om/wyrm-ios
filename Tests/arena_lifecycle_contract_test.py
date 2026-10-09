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
main = (ROOT / "SourcesOriginal" / "Main.m").read_text(encoding="utf-8")
mailbox = (ROOT / "SourcesOriginal" / "HomeMailbox.inc").read_text(encoding="utf-8")
generated = ROOT / "build-original-source" / "app" / "src"
game_data = (generated / "game" / "game_data.c").read_text(encoding="utf-8")
loop = (generated / "game" / "loop.c").read_text(encoding="utf-8")
server = (generated / "network" / "server.c").read_text(encoding="utf-8")
callback = (generated / "network" / "callback.c").read_text(encoding="utf-8")
protocol = (generated / "network" / "arena_protocol.h").read_text(encoding="utf-8")
home = (generated / "platform" / "android_home.c").read_text(encoding="utf-8")

checks = {
    "directory active flag": "bytes[offset] <= 26" in services,
    # The web client's ping since 2026-10-09: ws://ip:80/ptc with the page's
    # Origin, through Network (ATS refuses a URLSession ws://); the game-port
    # TCP dial stays only as the custom-address fallback.
    "web ptc latency probe": 'URL(string: "ws://\\(arena.address):80/ptc")' in services
        and 'setAdditionalHeaders([("Origin", "https://slither.io")])' in services
        and "Data([112])" in services and "data.first == 112" in services,
    "custom address keeps the TCP fallback": "NWConnection(host: NWEndpoint.Host(arena.address), port: port, using: .tcp)" in services
        and "if arena.number == 0 { fallback() }" in services,
    "probe reports connect milliseconds": "DispatchTime.now().uptimeNanoseconds - probeStarted" in services and "elapsed / 1_000_000" in services,
    "bounded probe timeout": "private static let deadline = 2.5" in services and "queue.asyncAfter(deadline: .now() + Self.deadline)" in services,
    "directory refresh avoids fleet-wide game-port probes": "func refreshArenasLive() async" in services and "for arena in candidates { group.addTask" not in services,
    # Every listed machine is measured while the picker is open, eight at a
    # time, one ping per IP (2026-10-09; it was the first ten, one by one).
    "picker measures every machine, bounded": "func measurePickerArenas(preferredEndpoints:" in services
        and "while next < min(8, machines.count)" in services and "seenMachines.insert($0.address)" in services
        and "await services.measurePickerArenas" in design,
    # The directory's first byte only weights the web client's own pick; every
    # listed arena is shown (108 of 144 were hidden, e.g. 4817).
    "picker shows every directory arena": r"services.arenas.filter(\.active)" not in design and "let live = services.arenas\n" in design,
    "picker ranks top ten and can expand": "Array(ranked.prefix(10))" in design and "See all" in design,
    "custom addresses are validated and stored": "static func custom(_ raw: String)" in services and "savedArenaEndpoints = entries.prefix(20)" in design,
    "recent joins are kept separately from saved addresses": "recentArenaEndpoints = recent.prefix(5)" in design,
    "lowest measured latency is recommended": "if left != right { return left < right }" in services,
    # The chosen arena (this session's pick, else the saved one) beats the
    # lowest-ping recommendation, across launches too (2026-10-09).
    "explicit choice overrides automatic recommendation": "let pick = userSelectedArena ? arena : chosenArena" in design
        and '@AppStorage("wyrm.ios.arena.chosen")' in design and "return services.recommendedArena" in design,
    "two-second directory-only picker refresh": "Task.sleep(nanoseconds: 2_000_000_000)" in design,
    "no Swift alternate-server failover": "failoverArena(refused:" not in design and "engine.playOnline" not in design,
    "native refusal bridge": "WyrmIOSArenaRefusalSnapshot" in shell and "WyrmIOSPublishArenaRefusal" in home,
    "short silent life returns to lobby": "refused_short_life" in callback and "gdata->join_spawned = false" in callback and "gdata->curr_screen = LOBBY" in loop,
    "no death card before own spawn": "if (!refused_short_life && gdata->join_spawned)" in callback,
    # Vlither's TIMEOUT (5 s until a snake exists), shared with Android since
    # 2026-10-09 through arena_protocol.h.
    "Vlither five-second entry timeout": "ARENA_CONNECT_TIMEOUT_MS = 5000" in protocol and "SDL_GetTicks() - gdata->attempt_started_ms > ARENA_CONNECT_TIMEOUT_MS" in loop and "if (gdata->connection && !gdata->connection->is_closing &&" in loop,
    # One dial per Play request. server_connect says no only while the last
    # socket is still alive (nothing was dialled); a failed dial still returns
    # true and ends the attempt. The 50 ms wait (Android's, iOS too since
    # 2026-10-09) dials once that socket is gone, never after a failed dial.
    "one dial per Play request": "ios_retry_or_finish" not in loop and "gdata->join_attempts++" not in server
        and "if (gdata->connection) {" in server
        and server[server.index("bool server_connect("):server.index("void server_poll(")].count("return false;") == 1
        and "if (!gdata->connection && SDL_GetTicks() >= gdata->rejoin_at_ms)" in loop,
    "picker probes cancel before the native Play request": shell.index("WyrmArenaProbeGate.shared.beginPlay()") < shell.index("WyrmIOSRequestPlay(namePointer, addressPointer, false)") and "pending.forEach { $0.cancel() }" in services,
    "picker probes stay blocked until native socket is gone": "gdata->conn == DISCONNECTED && !gdata->connection" in main and "WyrmEngineArenaPortAvailable" in main and "guard arenaPortBusySeen else { return }" in shell,
    "Apple generated bridge has no JNI port callback": "void android_home_set_arena_port_available(bool available) {\n(void)available;\n}" in home,
    "same-frame failed join still publishes busy edge": main.count("publish_arena_port_availability();") == 2,
    "zero-second terminal refusal reaches Swift": "seconds < 0" in mailbox and "apple_refusal_sequence++" in mailbox,
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
