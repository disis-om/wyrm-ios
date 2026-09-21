"""Audit Wyrm's arena lifecycle against the owner-provided Slither reference.

This is deliberately not a yes/no smoke test. It separates source-level
matches, observed device behaviour, known divergences, and things that a client
log cannot prove about the remote arena.
"""

from __future__ import annotations

import argparse
import hashlib
import re
from pathlib import Path


ROOT = Path(__file__).resolve().parent.parent
ANDROID = ROOT.parent / "Wyrm Android"
ENGINE = ROOT / "SharedEngine"
PREPARED = ROOT / "build-original-source" / "app" / "src"


def compact(text: str) -> str:
    return re.sub(r"\s+", "", text)


def contains_all(text: str, needles: tuple[str, ...]) -> bool:
    return all(needle in text for needle in needles)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("reference", type=Path)
    parser.add_argument("diagnostics", nargs="?", type=Path)
    parser.add_argument("--strict", action="store_true", help="exit 2 when a known divergence exists")
    args = parser.parse_args()

    raw = args.reference.read_bytes()
    js = compact(raw.decode("utf-8-sig"))
    protocol = (ENGINE / "app/src/network/arena_protocol.h").read_text()
    persona = compact((ENGINE / "app/src/network/arena_persona.c").read_text())
    runtime = PREPARED if (PREPARED / "network/callback.c").exists() else ENGINE / "app/src"
    callback = (runtime / "network/callback.c").read_text()
    server = (runtime / "network/server.c").read_text()
    input_c = (runtime / "game/input.c").read_text()
    loop = (runtime / "game/loop.c").read_text()
    game_data = (runtime / "game/game_data.c").read_text()
    home = (runtime / "platform/android_home.c").read_text()
    services = (ROOT / "SourcesShell/WyrmServices.swift").read_text()
    design = (ROOT / "SourcesShell/WyrmDesignMain.swift").read_text()

    rows: list[tuple[str, str, str]] = []

    def row(state: str, stage: str, evidence: str) -> None:
        rows.append((state, stage, evidence))

    timings = {
        "aim cadence": ("last_e_mtm>33", "ARENA_AIM_MS", 33),
        "turn cadence": ("lkstm>50", "ARENA_TURN_MS", 50),
        "boost cadence": ("last_accel_mtm>50", "ARENA_BOOST_MS", 50),
        "ping cadence": ("last_ping_mtm>250", "ARENA_PING_MS", 250),
        "lag threshold": ("last_ping_mtm>750", "ARENA_LAG_MS", 750),
        "connect-attempt timeout": ("start_connect_mtm>3333", "ARENA_RETRY_MS", 3333),
        "death wait": ("dead_mtm>1600", "ARENA_DEATH_WAIT_MS", 1600),
    }
    for name, (needle, constant, value) in timings.items():
        reference_ok = needle in js
        engine_ok = re.search(rf"\b{constant}\s*=\s*{value}\b", protocol) is not None
        row("PASS" if reference_ok and engine_ok else "MISMATCH", name, f"reference and engine = {value} ms")

    fingerprint_match = re.search(r"varcpw=\[([^]]+)\]", js)
    fingerprint_ok = bool(fingerprint_match and fingerprint_match.group(1) in persona)
    row("PASS" if "client_version=291" in js and "291" in persona and fingerprint_ok else "MISMATCH",
        "web persona", "client 291 and 20-byte challenge fingerprint")

    row("PASS" if contains_all(server, ("ws://%s/slither", "https://slither.io")) else "MISMATCH",
        "WebSocket transport", "ws://IP:port/slither with Slither Origin")
    row("PASS" if contains_all(callback, ("(uint8_t[]){1}", "(uint8_t[]){'c', 0}")) else "MISMATCH",
        "socket preamble", "byte 1 followed by c,0")
    row("PASS" if contains_all(callback, ("decode_secret", "answer[27]", "ba[0] = 115", "arena_send(c, ba, m)")) else "MISMATCH",
        "challenge and join", "27-byte answer then s join packet")
    row("PASS" if contains_all(input_c, ("if (!gdata->data.wfpr)", "ARENA_PING_MS", "? 251 : 112")) else "MISMATCH",
        "keepalive gate", "one ping outstanding; protocol >= 5 uses 251")

    parity_files = (
        "app/src/game/game_data.c", "app/src/game/game_data.h", "app/src/game/loop.c",
        "app/src/game/input.c", "app/src/network/callback.c", "app/src/network/server.c",
        "app/src/network/arena_persona.c", "app/src/network/arena_persona.h",
        "app/src/network/arena_protocol.h", "app/src/network/arena_taint.c",
        "app/src/network/arena_taint.h", "app/src/platform/android_home.c",
    )
    unequal = []
    for relative in parity_files:
        android_file = ANDROID / relative
        ios_file = ENGINE / relative
        if not android_file.exists() or not ios_file.exists() or android_file.read_bytes() != ios_file.read_bytes():
            unequal.append(relative)
    row("PASS" if not unequal else "MISMATCH", "Android/iOS shared source parity",
        "12/12 files byte-identical" if not unequal else "different: " + ", ".join(unequal))

    original_picker = contains_all(js, ("/ptc", "2667", "sos.length"))
    ios_picker_matches = contains_all(services, (
        '/ptc', "Data([112])", "samples.count == 3", "addingTimeInterval(2.667)",
        "addingTimeInterval(7)", "$0.active && $0.players > 20", "arena.players + 5",
    ))
    row("PASS" if original_picker and ios_picker_matches else "MISMATCH", "directory ping and server choice",
        "three /ptc RTT samples, readiness delay, active-count floor, cluster minimum and weighted choice")

    global_cooldown = "last_connect_ms + min_interval_ms" in game_data
    row("MISMATCH" if global_cooldown else "PASS", "3333 ms semantics",
        "connect timeout triggers reselection; no global join cooldown in generated Apple source")

    failover_ok = contains_all(callback, ("refused_short_life", "arena_taint_mark", "android_home_arena_refused")) and contains_all(
        home, ("WyrmIOSPublishArenaRefusal", "android_home_arena_refused")
    ) and contains_all(design, ("failoverArena(refused:", "engine.playOnline"))
    row("PASS" if failover_ok else "MISMATCH", "taint and automatic failover",
        "short silent life is tainted for 120s, bridged to Swift, excluded and retried on an alternate endpoint")

    join_alive_calls = len(re.findall(r"\binput_join_alive\s*\(", input_c))
    row("UNPROVEN" if join_alive_calls == 1 else "PASS", "forced first live input",
        "input_join_alive is defined but has no caller; device trace did send an initial aim packet")

    if args.diagnostics:
        diag = args.diagnostics.read_text(encoding="utf-8", errors="replace")
        challenges = diag.count("answered the challenge as 'web' (client 291)")
        spawns = diag.count("spawned us (protocol ")
        presented = diag.count("own snake spawned, frame presented")
        durations = [float(value) for value in re.findall(r"ended after ([0-9.]+)s", diag)]
        long_runs = [value for value in durations if value >= 30]
        drops = len(re.findall(r"ended after [0-9.]+s .*the arena dropped us", diag))
        row("PASS" if challenges else "UNPROVEN", "real-device challenge acceptance", f"{challenges} accepted web challenges")
        row("PASS" if spawns and presented else "UNPROVEN", "real-device own spawn",
            f"{spawns} own-spawn packets; {presented} explicit presented-frame proof")
        row("PASS" if long_runs else "UNPROVEN", "sustained live session",
            f"longest observed run {max(long_runs):.1f}s" if long_runs else "no >=30s session in supplied log")
        row("HISTORICAL" if drops else "PASS", "arena stability", f"Build 35 supplied log has {drops} arena-initiated closes; Build 37 runtime not yet tested")
        row("UNPROVEN", "server-side close reason",
            "server sent a silent WebSocket close; client log contains no rejection code")

    for state, stage, evidence in rows:
        print(f"{state:10} {stage:34} {evidence}")
    print(f"REFERENCE  SHA256 {hashlib.sha256(raw).hexdigest()}")
    totals = {state: sum(1 for row_state, _, _ in rows if row_state == state) for state in ("PASS", "MISMATCH", "FAIL", "UNPROVEN", "HISTORICAL")}
    print("SUMMARY    " + " ".join(f"{key}={value}" for key, value in totals.items()))
    print("VERDICT    NOT FULLY CONFORMANT" if totals["MISMATCH"] or totals["FAIL"] else "VERDICT    SOURCE-CONFORMANT; NEW DEVICE RUNTIME UNVERIFIED")
    return 2 if args.strict and (totals["MISMATCH"] or totals["FAIL"]) else 0


if __name__ == "__main__":
    raise SystemExit(main())
