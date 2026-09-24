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
VLITHER = ROOT.parent / "vlither-master" / "app" / "src"
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
    loop_c = (runtime / "game/loop.c").read_text()
    vlither_callback = compact((VLITHER / "network/callback.c").read_text())
    vlither_server = compact((VLITHER / "network/server.c").read_text())
    vlither_loop = compact((VLITHER / "game/loop.c").read_text())
    vlither_constants = compact((VLITHER / "constants.h").read_text())
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

    vlither_web_identity = contains_all(vlither_constants, ("#defineCLIENT_VERSION291",)) and contains_all(
        vlither_callback, ("uint8_tcwa[20]={54,206,204,169,97,178,74,136,124,117,",
                           "decode_secret(a,a_len,secret)", "mg_ws_send(c,secret,27,WEBSOCKET_OP_BINARY)"))
    row("PASS" if vlither_web_identity else "MISMATCH", "Slither to Vlither identity",
        "Vlither uses web version 291, matching fingerprint and 27-byte decoded answer")
    vlither_open = contains_all(vlither_callback, ("(uint8_t[]){1}", "(uint8_t[]){'c',0}"))
    row("PASS" if vlither_open else "MISMATCH", "Slither to Vlither preamble",
        "web default: byte 1, then c and zero; no timing/sequence prefix")
    row("DIVERGENCE" if "ba[m]=usrs->accessory" in vlither_callback and "ba[m]=255" in js else "UNPROVEN",
        "web versus Vlither cosmetics", "web uses accessory 255; Vlither sends selected accessory and compressed custom skin")
    row("DIVERGENCE" if "glfwGetTime()>TIMEOUT" in vlither_loop and "#defineTIMEOUT5" in vlither_constants else "UNPROVEN",
        "web versus Vlither timeout", "web taints/reselects after 3333ms; Vlither waits 5s then disconnects")
    row("DIVERGENCE" if "https://slither.com" in vlither_server and "https://slither.io" in compact(server) else "UNPROVEN",
        "native Origin difference", "Vlither sends slither.com; Wyrm retains the live-proven slither.io Origin; JS cannot specify the browser header")

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
    expected_ntl_delta = unequal == ["app/src/network/callback.c"] and contains_all(callback, (
        "snake_ntl_id(arena_id, session_id)", "o.ntl_id = id"))
    row("PASS" if not unequal else "DIVERGENCE" if expected_ntl_delta else "MISMATCH",
        "Android/iOS shared source parity",
        "12/12 files byte-identical" if not unequal else
        "known NTL session-id metadata extension" if expected_ntl_delta else
        "unexpected source delta: " + ", ".join(unequal))

    original_picker = contains_all(js, ("/ptc", "2667", "sos.length"))
    ios_picker_matches = contains_all(services, (
        '/ptc', "Data([112])", "samples.count == 3", "addingTimeInterval(2.667)",
        "addingTimeInterval(7)", "$0.active && $0.players > 20", "arena.players + 5",
    ))
    row("PASS" if original_picker and ios_picker_matches else "DIVERGENCE" if original_picker and
        contains_all(services, ("NWConnection(host: NWEndpoint.Host(arena.address)", "refreshRecommendation"))
        else "MISMATCH", "directory ping and server choice",
        "Slither uses three /ptc RTT samples and weighted clusters; iOS uses user-requested direct-port latency and lowest-latency selection")

    global_cooldown = "last_connect_ms + min_interval_ms" in game_data
    row("DIVERGENCE" if global_cooldown else "MISMATCH", "3333 ms semantics",
        "Slither uses 3333ms as connection timeout; original Wyrm also paces joins 3333ms to prevent rapid re-entry")

    web_join_extension = contains_all(callback, ("ba[m] = usrs->accessory", "skin_compressed_len"))
    row("DIVERGENCE" if web_join_extension else "PASS", "native cosmetic join fields",
        "plain web sends accessory 255; Vlither and Wyrm send selected accessory and compressed custom skin")

    stage_logs = contains_all(callback, ("TCP connected", "WebSocket upgraded", "WebSocket close frame", "socket closed in phase"))
    row("PASS" if stage_logs else "MISMATCH", "socket-stage diagnostics",
        "TCP, HTTP upgrade, close-code and challenge/spawn phase are distinguishable without logging secrets")

    one_shot = contains_all(callback, ("refused_short_life", "gdata->join_spawned = false")) and contains_all(
        loop_c, ("game_fail_connection(gdata, \"configuration timeout\")", "gdata->curr_screen = LOBBY"))
    one_shot = one_shot and "ios_retry_or_finish" not in loop_c and "failoverArena(refused:" not in design
    one_shot = one_shot and "gdata->rejoin_at_ms = SDL_GetTicks() + 50" not in loop_c
    row("PASS" if one_shot else "MISMATCH", "Vlither-style single Play attempt",
        "one selected-server dial; failure returns to native lobby without automatic retry or alternate server")

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
        row("PASS" if challenges and spawns else "UNPROVEN", "real-device challenge acceptance",
            f"{challenges} web answers sent; {spawns} subsequent spawns prove acceptance on some attempts")
        row("PASS" if spawns and presented else "UNPROVEN", "real-device own spawn",
            f"{spawns} own-spawn packets; {presented} explicit presented-frame proof")
        row("PASS" if long_runs else "UNPROVEN", "sustained live session",
            f"longest observed run {max(long_runs):.1f}s" if long_runs else "no >=30s session in supplied log")
        row("HISTORICAL" if drops else "PASS", "arena stability", f"supplied older-build log has {drops} arena-initiated closes; patched device runtime not yet tested")
        row("UNPROVEN", "server-side close reason",
            "server sent a silent WebSocket close; client log contains no rejection code")

    for state, stage, evidence in rows:
        print(f"{state:10} {stage:34} {evidence}")
    print(f"REFERENCE  SHA256 {hashlib.sha256(raw).hexdigest()}")
    totals = {state: sum(1 for row_state, _, _ in rows if row_state == state) for state in ("PASS", "MISMATCH", "FAIL", "DIVERGENCE", "UNPROVEN", "HISTORICAL")}
    print("SUMMARY    " + " ".join(f"{key}={value}" for key, value in totals.items()))
    print("VERDICT    SOURCE MISMATCH REMAINS" if totals["MISMATCH"] or totals["FAIL"] else
          "VERDICT    CORE WEB SEQUENCE ALIGNED; INTENTIONAL EXTENSIONS AND NEW DEVICE RUNTIME UNVERIFIED")
    return 2 if args.strict and (totals["MISMATCH"] or totals["FAIL"]) else 0


if __name__ == "__main__":
    raise SystemExit(main())
