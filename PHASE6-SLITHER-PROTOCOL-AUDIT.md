# Phase 6 — Slither protocol and arena lifecycle audit

Audit date: 2026-09-21  
Reference: owner-provided `C:\Users\Om Rajput\Downloads\Slither.txt`  
Runtime evidence: Wyrm iOS Build 35 diagnostics from an iPhone  
Implementation baseline: Build 37 source after the audit fixes; Build 35 remains the supplied physical-device evidence.

## Verdict

Build 37 source has **no known lifecycle divergence** from the owner-provided Slither reference in the audited stages. It keeps the byte-identical Android engine baseline, then applies Apple-only generated-source adapters for refusal reporting and retry semantics.

This is source and portable-test evidence, not a claim that Build 37 has already passed on a physical iPhone. Build 35 still contains repeated arena-initiated closes after successful spawn. The supplied client log has no server rejection code, so the exact remote reason remains unknown until the new build is tested.

## Stage-by-stage result

| Stage | Result | Evidence |
|---|---|---|
| Directory decode | Pass | iOS decodes the live `i80124.txt` arena directory into IP, port, players, cluster, and arena number. |
| Directory ping/readiness | Pass in Build 37 source | iOS opens `ws://IP:80/ptc`, sends binary `p`, requires binary `p`, takes three RTT samples, uses the minimum, waits 2667 ms after the first successful probe, and retains the 7000 ms directory fallback. |
| Server choice | Pass in Build 37 source | Active arenas with more than 20 players are eligible; the lowest-ping cluster is chosen and its arenas are weighted by `activeCount + 5`. Tainted endpoints are excluded. |
| WebSocket URL and Origin | Pass | Native engine opens `ws://IP:port/slither` with the Slither Origin. |
| Initial handshake | Pass | Native engine sends byte `1`, then the Web persona's `c,0`. |
| Challenge decoding | Pass | The challenge decoder creates the required 27-byte answer. Device logs show the live server accepted this repeatedly as web client 291. |
| Client identity | Pass | Web client version 291 and the 20-byte fingerprint match the reference. |
| Join payload | Pass | Native engine sends the `s` join packet after the answer. Device traces contain `0x73` and then live spawn. |
| Config and spawn | Pass | The live arena selected protocol 19 and sent the own-snake spawn; the engine presented the frame. |
| Packet decoder safety | Pass | Fresh native test passed timing checks, v2/v3/v6/v14 turn decoders, minimaps, packet boundaries, and 100,000 bounded malformed inputs. |
| Ping cadence | Pass | One ping is allowed outstanding; protocol 5+ uses byte 251; the reply clears the gate. Reference threshold is 250 ms. |
| Aim/turn/boost cadence | Pass | 33/50/50 ms constants match the reference. Build 35 live traces show 250–302 ms maximum aggregate send gaps during short attempts and 267 ms during the sustained session. |
| Lag threshold | Pass | 750 ms matches the reference. |
| Death wait/fade | Source match | 1600 ms and `.004 * vfr` match the reference. |
| Connect attempt timeout | Pass | No config after 3333 ms triggers failure handling. |
| 3333 ms re-entry meaning | Pass in Build 37 source | It is only the current connect-attempt timeout; the Apple generated source no longer imposes a global join cooldown. |
| 120 s taint | Pass in Build 37 source | Pre-config refusal and silent short-life closure taint the endpoint for 120 seconds and publish the refusal through the Apple mailbox. |
| Automatic failover | Pass in Build 37 source | Swift consumes the native refusal sequence, excludes the refused endpoint, chooses another eligible arena, and calls the original engine's online play bridge. |
| First forced live input | Unproven | `input_join_alive()` exists but has no caller. Build 35 nevertheless emitted an initial aim packet (`0x8E`) on every shown attempt, so this is a latent coverage gap rather than a proven cause of the closes. |
| Server close reason | Unproven | The server closed silently after already spawning the snake; there was no preceding client-side transport error or rejection packet. |

## What the physical iPhone log proves

For `148.113.20.151:444`, Build 35 repeatedly completed:

1. WebSocket connection.
2. Web client 291 challenge response.
3. Protocol 19 negotiation.
4. Own-snake spawn and presented frame.
5. Live inbound world traffic and outbound aim/ping traffic.

Three early attempts were dropped after roughly 0.2 s, 0.6 s, and 0.5 s. A later attempt ran for 126.7 s with 3,505 outbound and 58,612 inbound packets and ended by the client. Later re-entry attempts were again dropped after roughly 0.4 s, 0.4 s, and 0.3 s.

This rules out “the handshake is totally wrong” as a general explanation: the same handshake produced a sustained match. It does **not** rule out arena-side admission/rate limiting, re-entry policy, or a session-state edge case, because the arena emitted no reason code.

## Shared Android/iOS engine status

The audited gameplay/network files in Android and iOS `SharedEngine` are byte-identical (12/12 checked). Therefore, the lifecycle defects above are shared-engine defects unless they are specifically in the Swift directory picker or the Apple adapter. Android should remain read-only until a separate implementation turn is explicitly approved.

## Build 37 verification gates

1. `Tests/arena_lifecycle_contract_test.py` checks 13 generated-source and Swift lifecycle contracts.
2. `verify-slither-reference.py` currently reports 19 pass, 0 mismatch, 0 current fail, 2 unproven, and 1 historical Build 35 failure.
3. Cloud Xcode must compile both iPhoneOS and Simulator targets and pass the synthetic native-refusal mailbox smoke test.
4. Physical-device testing must still prove that the arena admits, renders, survives re-entry, and automatically changes endpoint after an actual refusal.

## Re-run command

```powershell
python "C:\Users\Om Rajput\Desktop\wyrm\Wyrm iOS\Scripts\verify-slither-reference.py" `
  "C:\Users\Om Rajput\Downloads\Slither.txt" `
  "C:\Users\Om Rajput\Downloads\Wyrm-diagnostics-1789929530.txt"
```

For a CI-style failure when known source mismatches remain, add `--strict`. Historical Build 35 evidence is reported separately and does not masquerade as a Build 37 result.
