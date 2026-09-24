#!/usr/bin/env python3
"""Source-level contracts for the full-screen SwiftUI shell."""

from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
COMPONENTS = (ROOT / "SourcesShell" / "WyrmDesignComponents.swift").read_text(encoding="utf-8")
DETAILS = (ROOT / "SourcesShell" / "WyrmDesignDetails.swift").read_text(encoding="utf-8")
MAIN = (ROOT / "SourcesShell" / "WyrmDesignMain.swift").read_text(encoding="utf-8")
PARITY = (ROOT / "SourcesShell" / "AndroidParityShell.swift").read_text(encoding="utf-8")
LEGACY = (ROOT / "SourcesShell" / "WyrmShell.swift").read_text(encoding="utf-8")
PAGES = (ROOT / "SourcesShell" / "WyrmSettingsPages.swift").read_text(encoding="utf-8")
KIT = (ROOT / "SourcesShell" / "WyrmSettingsKit.swift").read_text(encoding="utf-8")
THEME = (ROOT / "SourcesShell" / "WyrmTheme.swift").read_text(encoding="utf-8")
SHELL_C = (ROOT / "SourcesOriginal" / "WyrmShell.c").read_text(encoding="utf-8")
LOBBY = (ROOT / "SourcesShell" / "WyrmLobby.swift").read_text(encoding="utf-8")
ENTRY = (ROOT / "SourcesShell" / "WyrmDesignEntry.swift").read_text(encoding="utf-8")
MAIN_M = (ROOT / "SourcesOriginal" / "Main.m").read_text(encoding="utf-8")
MAILBOX = (ROOT / "SourcesOriginal" / "HomeMailbox.inc").read_text(encoding="utf-8")


checks = {
    "paper background is one full-bleed colour": "ATheme.paper.ignoresSafeArea()" in COMPONENTS,
    "root shell fills every safe-area edge": MAIN.count(".ignoresSafeArea()") >= 3,
    "detail routes paint their own full-screen paper canvas": "ATheme.paper.ignoresSafeArea()" in MAIN,
    "floating tab bar does not reserve a footer": ".padding(.bottom, 66 + tabBarBottomInset)" not in MAIN,
    "root scroll views can pass behind the floating tab bar": (MAIN + PAGES).count("Spacer().frame(height: 102)") >= 4 and ".padding(.bottom, 108)" in (ROOT / "SourcesShell" / "WyrmSkinStudio.swift").read_text(encoding="utf-8"),
    "tab lens receives drags above tab buttons": ".highPriorityGesture(DragGesture(minimumDistance: 2" in COMPONENTS,
    "iOS 26 bar and lens keep independent glass layers": COMPONENTS.count("GlassEffectContainer(spacing: 0)") >= 2 and "glassEffectID" not in COMPONENTS,
    "iOS 26 base and pill glass are interactive": COMPONENTS.count(".interactive()") >= 2,
    "selected lens does not use an opaque ink tint": ".regular.tint(ATheme.ink" not in COMPONENTS,
    "setting rows keep stable identity during live refresh": ".id(row.id + row.displayValue)" not in DETAILS + PARITY + LEGACY,
    "engine writes stay optimistic until the engine echoes them": "settingOverrides[setting.id] = (values, Date().addingTimeInterval(1.8))" in LEGACY
        and "incoming[index].values = pending.values" in LEGACY,
    "hotkey writes stay optimistic until the engine echoes them": "hotkeyOverrides[hotkey.id] = (hotkey, Date().addingTimeInterval(1.8))" in LEGACY,
    "store publishes only when the engine snapshot changed": "if incoming != settings { settings = incoming }" in LEGACY,
    "layout positions write both axes together": "queue(prefix, [safeX, safeY]" in LEGACY,
    "every Android settings page has an iOS page": all(name in PAGES for name in (
        "struct WyrmDisplayPage", "struct WyrmControlsContent", "struct WyrmButtonsContent", "struct WyrmArenaUIContent",
        "struct WyrmModesPage", "struct WyrmBotPage", "struct WyrmFoodPage", "struct WyrmNotificationSettingsPage",
        "struct WyrmPrivacyPage", "struct WyrmAccessibilityPage", "struct WyrmBackupPage", "struct WyrmLayoutEditor")),
    "old engine-settings detail list is gone": "WyrmEngineSettingsDetail" not in DETAILS and "WyrmSettingsRoot" not in MAIN,
    "loadout opens Play-scoped settings": all(r in MAIN for r in ("open(.playFood)", "open(.playControls)", "open(.playModes)")),
    "restore respects the 128-change engine mailbox": "index += 60" in PAGES and "Task.sleep(nanoseconds: 250_000_000)" in PAGES,
    "backups never carry account or Team secrets": "Keychain" in PAGES and "wyrm.ios.skin." in PAGES and "token" not in PAGES.split("struct WyrmBackup: Codable")[1].split("struct WyrmBackupDocument")[0],
    "eight Android themes with intensity": THEME.count("case .") >= 16 and "func withIntensity(_ intensity: Double) -> WyrmPalette" in THEME,
    "theme reaches the engine atomically": "arena_theme_set(next, dark)" in SHELL_C and "WyrmIOSSetArenaTheme" in THEME,
    "tab lens lifts and settles with a spring": "lifted" in COMPONENTS and ".interpolatingSpring(stiffness: 320, damping: 14)" in COMPONENTS,
    "Ready Room follows Android placement and theme": all(s in LOBBY for s in (
        "Ready room", "Enter the arena", "Selected arena", "Playing as", "Quick settings", "Play with AI", "WyrmBrandStroke()"))
        and "ATheme.paper" in LOBBY,
    "shell stays above the engine for lobby and editor": "reported_screen == LOBBY || shell_overlay" in MAIN_M
        and "WyrmEngineScreenChanged" in MAIN_M and "UIColor.clearColor" in MAIN_M,
    "layout editor runs over the original AI editor arena": "pending_ai_editor_enter = true" in MAILBOX
        and "engine.openLayoutEditor()" in PAGES and "fullScreenCover(isPresented: $editing)" not in PAGES
        and ".opacity(0.012)" in PAGES,
    "segmented pills and switches are system Liquid Glass controls": ".pickerStyle(.segmented)" in KIT and "Toggle(\"\", isOn:" in KIT,
    "cold start syncs behind the launch mark": "launchSyncing" in ENTRY and "WyrmDesignLaunch()" in ENTRY,
    "tab pill rests plain and lifts into clear glass": "Glass.clear.interactive()" in COMPONENTS and ".opacity(lifted ? 0 : 1)" in COMPONENTS,
    "no GitHub in player-visible settings copy": "GitHub" not in PAGES and "GitHub" not in KIT,
    "tab drag uses absolute finger location": "value.location.x" in COMPONENTS and "predictedEndTranslation" not in COMPONENTS,
    "tab drag snaps to nearest absolute slot": "nearestIndex(at: value.location.x - inset" in COMPONENTS,
}

failed = [name for name, ok in checks.items() if not ok]
for name, ok in checks.items():
    print(f"{'PASS' if ok else 'FAIL'}: {name}")

if failed:
    raise SystemExit(f"{len(failed)} UI shell contract(s) failed")

print(f"UI shell contracts: {len(checks)}/{len(checks)} passed")
