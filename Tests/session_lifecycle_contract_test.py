#!/usr/bin/env python3
"""Source contracts for clean account transitions and fresh service state."""

from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
ACCOUNT = (ROOT / "SourcesShell/WyrmAccount.swift").read_text(encoding="utf-8")
AUTH = (ROOT / "SourcesShell/WyrmCinematicAuth.swift").read_text(encoding="utf-8")
ENTRY = (ROOT / "SourcesShell/WyrmDesignEntry.swift").read_text(encoding="utf-8")
SERVICES = (ROOT / "SourcesShell/WyrmServices.swift").read_text(encoding="utf-8")

checks = {
    "sign out has an explicit transition phase": "case restoring, signedOut, onboarding, signedIn, signingOut" in ACCOUNT,
    "sign out waits for shell cleanup": "func completeSignOut()" in ACCOUNT and "services.resetSession()" in ENTRY,
    "sign out uses the W cinematic": 'WyrmSessionTransition(title: "Signing you out…")' in ENTRY,
    "authentication bootstraps before completing": AUTH.index("await services.bootstrap") < AUTH.index("account.completeAuthentication()"),
    "home is gated on prepared account data": "services.isPrepared(for: account.player?.id)" in ENTRY,
    "service sessions invalidate stale requests": "sessionRevision = revision" in SERVICES and "sessionRevision == revision" in SERVICES,
    "all account-scoped collections are cleared": all(
        token in SERVICES
        for token in ["alerts = []", "conversations = []", "followers = []", "following = []", "messages = []"]
    ),
    "bootstrap isolates endpoint failures": SERVICES.count("try? await WyrmServiceClient.shared") >= 9,
}

failed = [name for name, ok in checks.items() if not ok]
for name, ok in checks.items():
    print(f"{'PASS' if ok else 'FAIL'}: {name}")
if failed:
    raise SystemExit(f"{len(failed)} session lifecycle contract(s) failed")
print(f"Session lifecycle contracts: {len(checks)}/{len(checks)} passed")
