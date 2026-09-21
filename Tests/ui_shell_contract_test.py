#!/usr/bin/env python3
"""Source-level contracts for the full-screen SwiftUI shell."""

from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
COMPONENTS = (ROOT / "SourcesShell" / "WyrmDesignComponents.swift").read_text(encoding="utf-8")
DETAILS = (ROOT / "SourcesShell" / "WyrmDesignDetails.swift").read_text(encoding="utf-8")
MAIN = (ROOT / "SourcesShell" / "WyrmDesignMain.swift").read_text(encoding="utf-8")
PARITY = (ROOT / "SourcesShell" / "AndroidParityShell.swift").read_text(encoding="utf-8")
LEGACY = (ROOT / "SourcesShell" / "WyrmShell.swift").read_text(encoding="utf-8")


checks = {
    "paper background is one full-bleed colour": "ATheme.paper.ignoresSafeArea()" in COMPONENTS,
    "root shell fills every safe-area edge": MAIN.count(".ignoresSafeArea()") >= 3,
    "detail routes paint their own full-screen paper canvas": "ATheme.paper.ignoresSafeArea()" in MAIN,
    "floating tab bar does not reserve a footer": ".padding(.bottom, 66 + tabBarBottomInset)" not in MAIN,
    "root scroll views can pass behind the floating tab bar": MAIN.count("Spacer().frame(height: 102)") >= 5,
    "tab lens receives drags above tab buttons": ".highPriorityGesture(DragGesture(minimumDistance: 2" in COMPONENTS,
    "iOS 26 glass is grouped": "GlassEffectContainer(spacing: 12)" in COMPONENTS,
    "iOS 26 base and pill glass are interactive": COMPONENTS.count(".interactive()") >= 2,
    "setting rows keep stable identity during live refresh": ".id(row.id + row.displayValue)" not in DETAILS + PARITY + LEGACY,
    "slider ignores external refresh while finger is down": "if !isDragging { value = row.values.first ?? value }" in DETAILS,
}

failed = [name for name, ok in checks.items() if not ok]
for name, ok in checks.items():
    print(f"{'PASS' if ok else 'FAIL'}: {name}")

if failed:
    raise SystemExit(f"{len(failed)} UI shell contract(s) failed")

print(f"UI shell contracts: {len(checks)}/{len(checks)} passed")
