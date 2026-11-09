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
ACCOUNT_SYNC = (ROOT / "SourcesShell" / "WyrmAccountSync.swift").read_text(encoding="utf-8")
KIT = (ROOT / "SourcesShell" / "WyrmSettingsKit.swift").read_text(encoding="utf-8")
THEME = (ROOT / "SourcesShell" / "WyrmTheme.swift").read_text(encoding="utf-8")
SHELL_C = (ROOT / "SourcesOriginal" / "WyrmShell.c").read_text(encoding="utf-8")
LOBBY = (ROOT / "SourcesShell" / "WyrmLobby.swift").read_text(encoding="utf-8")
ENTRY = (ROOT / "SourcesShell" / "WyrmDesignEntry.swift").read_text(encoding="utf-8")
MAIN_M = (ROOT / "SourcesOriginal" / "Main.m").read_text(encoding="utf-8")
MAILBOX = (ROOT / "SourcesOriginal" / "HomeMailbox.inc").read_text(encoding="utf-8")
SYNC = (ROOT / "SourcesShell" / "WyrmGameSync.swift").read_text(encoding="utf-8")
ARROWS = (ROOT / "SourcesShell" / "WyrmArrowSkins.swift").read_text(encoding="utf-8")
ARROWS_C = (ROOT / "SourcesOriginal" / "AppleArrowSkins.c").read_text(encoding="utf-8")
SPEC = (ROOT / "original-engine.yml").read_text(encoding="utf-8")
PREPARE = (ROOT / "Scripts" / "prepare-original-engine.py").read_text(encoding="utf-8")
ACCOUNT = (ROOT / "SourcesShell" / "WyrmAccount.swift").read_text(encoding="utf-8")
SERVICES = (ROOT / "SourcesShell" / "WyrmServices.swift").read_text(encoding="utf-8")
KEYBOARD = (ROOT / "SourcesShell" / "WyrmKeyboard.swift").read_text(encoding="utf-8")
CHAT = (ROOT / "SourcesShell" / "WyrmChatUI.swift").read_text(encoding="utf-8")
SEARCH = (ROOT / "SourcesShell" / "WyrmSettingsSearch.swift").read_text(encoding="utf-8")
SOCIAL = (ROOT / "SourcesShell" / "WyrmSocialExtras.swift").read_text(encoding="utf-8")
RUN_CAPTURE = (ROOT / "SourcesShell" / "WyrmRunCapture.swift").read_text(encoding="utf-8")
RUN_CAPTURE_C = (ROOT / "SourcesOriginal" / "AppleRunCapture.inc").read_text(encoding="utf-8")


checks = {
    "paper background is one full-bleed colour": "wyrmScopedColours.paper.ignoresSafeArea()" in COMPONENTS,
    "root shell fills every safe-area edge": MAIN.count(".ignoresSafeArea()") >= 3,
    "detail routes paint their own full-screen paper canvas": "wyrmScopedColours.paper.ignoresSafeArea()" in MAIN,
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
    "restore respects the 128-change engine mailbox": "index % 40 == 0" in ACCOUNT_SYNC and "Task.sleep(nanoseconds: 150_000_000)" in ACCOUNT_SYNC,
    "account settings never carry account or Team secrets": "wyrm.ios.skin." in ACCOUNT_SYNC and "token" not in ACCOUNT_SYNC.split("func platformDocument()")[1].split("// MARK: restore")[0] and "Keychain" not in ACCOUNT_SYNC,
    "22 current plus 8 classic themes with intensity": (ROOT / "SourcesShell/WyrmThemeTables.swift").read_text(encoding="utf-8").count("return (WyrmPalette(") == 30 and "func withIntensity(_ intensity: Double) -> WyrmPalette" in THEME,
    "theme reaches the engine atomically": "arena_theme_set(next, dark)" in SHELL_C and "WyrmIOSSetArenaTheme" in THEME,
    "tab lens lifts and settles with a spring": "lifted" in COMPONENTS and ".interpolatingSpring(stiffness: 240, damping: 10)" in COMPONENTS and "WyrmTabPillMotion" in COMPONENTS and ".zIndex(4)" in COMPONENTS,
    "Ready Room follows Android placement and theme": all(s in LOBBY for s in (
        "Ready room", "Enter the arena", "Selected arena", "Playing as", "Quick settings", "Play with AI", "WyrmBrandStroke()"))
        and "wyrmScopedColours.paper" in LOBBY,
    "shell stays above the engine for lobby and editor": "reported_screen == LOBBY || shell_overlay" in MAIN_M
        and "WyrmEngineScreenChanged" in MAIN_M and "UIColor.clearColor" in MAIN_M,
    "layout editor runs over the original AI editor arena": "pending_ai_editor_enter = true" in MAILBOX
        and "engine.openLayoutEditor()" in PAGES and "fullScreenCover(isPresented: $editing)" not in PAGES
        and ".opacity(0.012)" in PAGES,
    "segmented pills and switches are system Liquid Glass controls": ".pickerStyle(.segmented)" in KIT and "Toggle(\"\", isOn:" in KIT,
    "cold start syncs behind the launch mark": "launchSyncing" in ENTRY and "WyrmDesignLaunch()" in ENTRY,
    "tab pill rests plain and lifts into clear glass": "Glass.clear.interactive()" in COMPONENTS and ".opacity(lifted ? 0 : 1)" in COMPONENTS,
    "finished runs reach /v1/me/stats through a durable outbox": "WyrmIOSRecordFinishedRun(env->usr->usrs.score" in PREPARE
        and "/v1/me/stats" in SYNC and "eventId" in SYNC and "wyrm.ios.runs.pending" in SYNC,
    "the last run keeps its length and a death-frame screenshot": "env->usr->usrs.play_time" in PREPARE
        and "wyrm_capture_record(context);" in PREPARE and "wyrm_capture_harvest(context);" in PREPARE
        and "AppleRunCapture.inc" in PREPARE and "vkGetFenceStatus" in RUN_CAPTURE_C
        and "vkWaitForFences" not in RUN_CAPTURE_C and "VK_IMAGE_USAGE_TRANSFER_SRC_BIT) != 0" in RUN_CAPTURE_C
        and "parts.count == 2 || parts.count == 3" in SYNC and "WyrmRunCapture.record(" in SYNC
        and "wyrm_last_death_set(" in PREPARE
        and "WyrmRunCapture.runStarted()" in LEGACY
        and 'Notification.Name("WyrmRunCaptureChanged")' in RUN_CAPTURE
        and "static var lastRun: WyrmLastRun?" in RUN_CAPTURE and "let screenshot: UIImage?" in RUN_CAPTURE,
    "local totals reconcile every five hours": "/v1/me/stats/reconcile" in SYNC and "5 * 3600" in SYNC,
    "custom skins publish, heartbeat, clear and look up": all(s in SYNC for s in ('"/v1/arena/skin", method: "POST"',
        '"/v1/arena/skin", method: "DELETE"', '"/v1/arena/skins"', "60_000_000_000")) and "WyrmIOSArenaSyncPoll(env);" in PREPARE,
    "arena skin mailbox stays off the network and online-only": "!gdata->ai_mode && gdata->curr_screen == PLAYING" in MAILBOX,
    "own avatar path is made absolute": 'rawAvatar.hasPrefix("/")' in ACCOUNT,
    "avatar upload and renames use the Android routes": "/v1/me/avatar" in ACCOUNT and "/v1/me/renames" in ACCOUNT,
    "global chat and fresh profiles": "/v1/chat/messages" in SERVICES and '"/v1/players/' in SERVICES,
    "in-game name follows the account (any 1-24 characters, 2026-10-14)": "syncIngameName" in SYNC and "name.count <= 24" in SYNC and "[A-Za-z0-9_]{3,20}" not in SYNC,
    "twenty image arrows plus the five drawn styles in one picker": ARROWS.count('", "') >= 15 and "Vanced arrow" not in ARROWS
        and "WyrmArrowShapes.points.count" in ARROWS and (ROOT / "Resources" / "ArrowSkins.png").exists(),
    "image arrows are one atlas drawn as a rotated quad": "ImDrawList_AddImageQuad" in ARROWS_C and "WyrmIOSDrawArrowImage(dl, ax, ay, dx, dy, length," in PREPARE
        and "atlas_sampler" in ARROWS_C
        and "SourcesOriginal/AppleArrowSkins.c" in SPEC and "Resources/ArrowSkins.png" in SPEC,
    "brightness reaches drawn and image arrows; colour only the drawn": "wyrm_brightness" in PREPARE and "if store.skin < 0, let colour" in ARROWS,
    "one in-game name: Play and the Ready Room both write the engine's": "func setNickname(_ raw: String)" in LEGACY
        and "nicknameOverride" in LEGACY and "engine.setNickname(clean)" in MAIN and "engine.setNickname(clean)" in LOBBY,
    "a restart keeps the engine's saved name": "account.player?.arenaName ?? engine.nickname" not in MAIN and "adoptEngineName" in MAIN,
    "no GitHub in player-visible settings copy": "GitHub" not in PAGES and "GitHub" not in KIT,
    "tab drag uses absolute finger location": "value.location.x" in COMPONENTS and "predictedEndTranslation" not in COMPONENTS,
    "tab drag snaps to nearest absolute slot": "nearestIndex(at: value.location.x - inset" in COMPONENTS,
    "text fields keep their native iOS input view": "class_addMethod" not in KEYBOARD
        and "#selector(getter: UITextField.inputView)" not in KEYBOARD
        and "WyrmKeyboardController.shared.install()" in LEGACY,
    "native keyboard frame is converted into window coordinates": "keyboardWillChangeFrameNotification" in KEYBOARD
        and "window.convert(frame, from: screen.coordinateSpace)" in KEYBOARD and "WyrmIOSSetKeyboardOcclusion" in KEYBOARD,
    "the lobby reserves one keyboard height and scrolls its name field": "WyrmKeyboardView" not in LOBBY
        and "visibleHeight(outer.size.height, occlusion: keyboard.occlusion)" in LOBBY and 'reader.scrollTo("lobby-name"' in LOBBY,
    "routes leave the keyboard region so fields rise above it": ".ignoresSafeArea(.container)" in MAIN and "keyboard.focused ? 0 : 1" in MAIN,
    # Global chat and DMs share one Discord-style room since 2026-10-30 (WyrmDiscordChat.swift).
    "chat room is shared by global chat and DMs": "WyrmDiscordChat(direct: false" in SOCIAL and "WyrmDiscordChat(direct: true" in DETAILS
        and "WyrmChatComposer(" in DETAILS and "GlassEffectContainer(spacing: 14)" in CHAT,
    "settings search sits on the hub with live controls": "WyrmSettingsSearchField(query: $search.query)" in PAGES
        and "WSTypedRow(setting: setting, first: true, engine: engine)" in SEARCH and "arrow.up.right" in SEARCH,
    "a search arrow scrolls to its setting and blinks it twice": "proxy.scrollTo(target, anchor: .center)" in KIT
        and "row.wyrmSettingAnchor(setting.id)" in KIT and "for _ in 0..<2" in SEARCH,
    "searched settings open the fold or mode that holds them": PAGES.count("WyrmSettingsFocus.shared") >= 5,
}

android = ROOT.parent / 'Wyrm Android'
kotlin = android / 'android/app/src/main/java/com/wyrm/omrajput'
checks.update({
    "name picker uses real body preview and continuous slider on iOS":
        'WyrmSnakeBodyPreview(nameScale: setting.number' in KIT
        and 'range: 0.5...2.5' in KIT,
    "preview label resolves from the packaged texture root":
        'res/textures/name_size_preview.png' in PAGES
        and 'app/res/textures/name_size_preview.png' not in PAGES,
    "name and chat size use the shared account keys on iOS":
        all(key in ACCOUNT_SYNC
            for key in ['snakeNameScale', 'arenaChatTextScale', 'general.name_font', 'layout.chat_text_scale']),
    "old three-choice name size has a document migration marker":
        'nameScaleV1' in ACCOUNT_SYNC,
    "chat text scale is independent of panel dimensions on iOS":
        'layout.chat_text_scale' in PAGES and 'TEXT SIZE' in PAGES,
    "leaderboard editor bounds use the engine's 241-wide ten-row geometry":
        '241 * boardUnit' in PAGES and '140*boardUnit' in PAGES,
})

# A standalone iOS CI checkout has no sibling Android project. Keep all iOS
# assertions above unconditional; exercise the extra parity assertions locally.
if kotlin.exists():
    android_overlay = (kotlin / 'ui/WyrmOverlay.kt').read_text(encoding='utf-8')
    android_sync = (kotlin / 'data/AccountSync.kt').read_text(encoding='utf-8')
    editor = (kotlin / 'ui/LayoutEditors.kt').read_text(encoding='utf-8')
    name_picker = (kotlin / 'ui/SnakeNameSizeSetting.kt').read_text(encoding='utf-8')
    checks['Android name preview is continuous'] = 'SnakeBodyPreview(' in name_picker and 'steps=0' in name_picker.replace(' ', '')
    checks['Android shared account keys match iOS'] = all(key in android_overlay and key in ACCOUNT_SYNC for key in ['snakeNameScale', 'arenaChatTextScale', 'general.name_font', 'layout.chat_text_scale'])
    checks['Android legacy name migration marker'] = 'nameScaleV1' in android_sync
    checks['Android independent chat text control'] = 'layout.chat_text_scale' in editor and 'TEXT SIZE' in editor
    checks['Android board bounds match engine'] = '241f * boardUnit' in editor and '140f*boardUnit' in editor
else:
    print('Sibling Android source absent; local-only Android parity checks skipped')

failed = [name for name, ok in checks.items() if not ok]
for name, ok in checks.items():
    print(f"{'PASS' if ok else 'FAIL'}: {name}")

if failed:
    raise SystemExit(f"{len(failed)} UI shell contract(s) failed")

print(f"UI shell contracts: {len(checks)}/{len(checks)} passed")
