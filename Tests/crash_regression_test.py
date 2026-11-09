"""Crash regression: execute production quit loop and check UI safety boundaries.

No Gradle, CI, app build or device interaction. SwiftUI runtime requires Apple.
"""
from pathlib import Path
import os
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
ANDROID = ROOT.parent / "Wyrm Android"
pages = (ROOT / "SourcesShell/WyrmSettingsPages.swift").read_text(encoding="utf-8")
modes = pages[pages.index("struct WyrmModesPage:"):pages.index("enum WyrmSpineWidth")]
assert modes.count("AnyView(VStack(alignment: .leading, spacing: 0)") == 6
for label in ["Snake", "Boost", "Arena colours", "Arena background", "Joystick guide"]:
    assert f'WSSectionLabel("{label}")' in modes
assert "if visibleMode == 1 { WyrmJoystickLaserSection" in modes
assert "modeContent(mode).id(mode)" in modes
controls = pages[pages.index("let zoomRows = engine.settings.filter"):pages.index("struct WyrmControlsPreview")]
assert controls.count("AnyView(VStack(alignment: .leading, spacing: 0)") == 4
assert '.onAppear { if zoomRows.contains(where: { WyrmSettingsFocus.shared.wants($0.id) }) { zoomOpen = true } }' in controls
shell = (ROOT / "SourcesShell/WyrmShell.swift").read_text(encoding="utf-8")
assert "Int(exactly: number.rounded()) ?? 0" in shell
assert "values[i].isFinite" in shell
support = (ROOT / "SourcesShell/WyrmSupport.swift").read_text(encoding="utf-8")
assert "String(json.prefix(40_000))" not in support
assert '"exception: ' in support and '"termination: ' in support
assert "depth < 128, remaining > 0" in support and "var remaining = 160" in support
assert 'record.screen ?? "Unknown (previous launch)"' in support
assert 'context["appVersion"] = record.appVersion' in support
assert 'appVersion: version, build: build' in support
assert 'crashedBuild == WyrmSupportContext.build ? WyrmSupportContext.appVersion : "unknown"' in support
assert '("wyrm.crash.running", .keep)' in (ROOT / "SourcesShell/WyrmAccountSync.swift").read_text(encoding="utf-8")
print("PASS: Modes sections, numeric guards, bounded diagnostics and previous-launch context source contracts")

if not ANDROID.exists():
    print("SKIP: Android production-loop and mesh checks (standalone iOS checkout)")
    raise SystemExit(0)

ui = ANDROID / "android/app/src/main/java/com/wyrm/omrajput/ui"
mesh = (ui / "WyrmSkins.kt").read_text(encoding="utf-8")
wardrobe = (ui / "AndroidSkinWardrobe.kt").read_text(encoding="utf-8")
assert "mesh.canvas.draw(" in mesh and "canvas.draw(target.nativeCanvas" in wardrobe
assert "vertices > xy.size / 2" in mesh and "indices % 3 != 0" in mesh
assert "!xy[i].isFinite()" in mesh and 'and 0xFFFF) >= vertices' in mesh
assert "SDK_INT > 33 || !target.isHardwareAccelerated" in mesh
assert "software.drawVertices" in mesh and "target.drawBitmap" in mesh
assert "coerceIn(1, 1536)" in mesh and "Do not recycle" in mesh
service = (ui.parent / "BackgroundPlayService.kt").read_text(encoding="utf-8")
assert service.index("ServiceCompat.startForeground(") < service.index("if (stopWanted || !inForeground)")
assert "if (pending) return" in service and "CPU lock unavailable" in service
print("PASS: Android mesh validation/bitmap route and foreground-service source contracts")

stub = r'''
typedef _Bool bool;
#define true 1
#define false 0
#define WYRM_SDL_JNI 1
typedef struct { bool swapchain_ok, last_present_succeeded; } Context;
typedef struct { bool closed; } Window;
typedef struct { struct { bool running; } config; Context* ctx; Window* wnd; void* kb; void* ms; } Env;
static Env* active; static int kind, polls, waits, renders, inputs, iterations;
static bool wyrm_background_tick(Env* e) { return kind == 2 && ++iterations == 1; }
static void twindow_poll_input(Window* w) { if (++polls == 3) w->closed = true; }
static void twindow_wait_input(Window* w) { if (++waits >= 3) w->closed = true; if (waits > 20) active->config.running = false; }
static bool twindow_closed(Window* w) { return w->closed; }
static void tinput(Env* e) { inputs++; if (e->wnd->closed) e->config.running = false; }
static void trender(Env* e) { (void)e; renders++; }
static bool wyrm_late_latch(Env* e) { (void)e; return false; }
static bool tcontext_acquire(Context* c) { (void)c; return false; }
static void twindow_pump_events(Window* w) { (void)w; }
static void tkeyboard_update(void* x) { (void)x; }
static void tmouse_update(void* x) { (void)x; }
static void android_startup_ready(void) {}
__attribute__((export_name("run"))) int run(int scenario) {
 kind=scenario; polls=waits=renders=inputs=iterations=0;
 Context ctx={scenario!=0,true}; Window wnd={false}; Env env={{true},&ctx,&wnd,0,0}; active=&env;
 bool startup_ready_reported=false;
 LOOP
 return renders | (inputs<<8) | (waits<<16);
}
'''
clang = Path(os.environ.get("LOCALAPPDATA", "")) / "Android/Sdk/ndk/28.2.13676358/toolchains/llvm/prebuilt/windows-x86_64/bin/clang.exe"
with tempfile.TemporaryDirectory(prefix="wyrm-crash-loop-") as tmp:
    tmp = Path(tmp)
    for label, folder in [("Android", ANDROID), ("Apple snapshot", ROOT / "SharedEngine")]:
        source = (folder / "thermite/src/core/tentry.c").read_text(encoding="utf-8")
        loop = source[source.index("  while (env.config.running)"):source.index("  tcontext_wait_idle(env.ctx);")]
        (tmp / "test.c").write_text(stub.replace("LOOP", loop), encoding="utf-8")
        subprocess.run([str(clang), "--target=wasm32", "-O1", "-nostdlib", "-Wl,--no-entry", str(tmp / "test.c"), "-o", str(tmp / "test.wasm")], check=True)
        script = r'''const fs=require('fs'),a=require('assert'); (async()=>{
          const {instance:{exports:x}}=await WebAssembly.instantiate(fs.readFileSync(process.argv[1]));
          a.equal(x.run(0), 3*65536+256, 'Quit while swapchain unavailable: no render, three waits, one settings-save input');
          a.equal(x.run(1), 3*256+2, 'Quit while drawable: do not render after close');
          a.equal(x.run(2), 3*256+2, 'Return from background still observes quit');
        })().catch(e=>{console.error(e);process.exit(1)});'''
        subprocess.run(["node", "-e", script, str(tmp / "test.wasm")], check=True)
        print(f"PASS: {label} production loop: lost surface, drawable and background quit")
print("Crash regression checks passed; Apple compile/device runtime remains unverified")
