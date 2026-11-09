"""Paper session defaults, account text parity and executable C migration policy.

Portable fixtures only: no APK/IPA build, device or live account operation.
"""
from pathlib import Path
import os
import re
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
ANDROID = ROOT.parent / "Wyrm Android"
def read(p): return p.read_text(encoding="utf-8")
def enclosing_if(text, target):
    """Track brace ownership around an action, ignoring comments and strings."""
    masked = re.sub(r'//[^\n]*|/\*[\s\S]*?\*/|"(?:\\.|[^"\\])*"', lambda m: ' ' * len(m[0]), text)
    stack = []
    for i, ch in enumerate(masked[:target]):
        if ch == '{': stack.append(i)
        elif ch == '}': stack.pop()
    return [masked[max(0, i-140):i].split('\n')[-1] for i in stack]
sync = read(ROOT / "SourcesShell/WyrmAccountSync.swift")
theme = read(ROOT / "SourcesShell/WyrmTheme.swift")
tables = read(ROOT / "SourcesShell/WyrmThemeTables.swift")
pages = read(ROOT / "SourcesShell/WyrmSettingsPages.swift")
assert 'case "": return (.classic_paper, .light)' in tables
assert 'defaults.set("grape"' not in theme
assert 'd.set("grape"' not in sync
assert 'if doc["themeRefreshV1"] as? Bool == true' not in sync
assert 'commitWork?.cancel()' in theme[theme.index('func reloadFromDefaults()'):]
assert '"general.native_text_style"' in pages[pages.index('struct WyrmDisplayPage:'):pages.index('// MARK: - Controls workspace')]
assert 'doc["nativeTextStyle"] = Int(value)' in sync
assert 'write(id: "general.native_text_style", values: [value.doubleValue])' in sync
assert 'CFGetTypeID(value) != CFBooleanGetTypeID(), value.doubleValue == 0 || value.doubleValue == 1' in sync
assert 'WyrmSettingsFocus.shared.query = ""' in sync
hub = pages[:pages.index('// MARK: - Display')]
assert not any('else' in owner for owner in enclosing_if(hub, hub.index('WSActionRow(title: "Log out"')))
print("PASS: iOS Paper default, marker-independent restore, local cleanup and shared text registry")
if not ANDROID.exists():
    print("SKIP: Android and native execution in standalone iOS checkout")
    raise SystemExit(0)

base = ANDROID / "android/app/src/main/java/com/wyrm/omrajput"
overlay = read(base / "ui/WyrmOverlay.kt")
account = read(base / "data/AccountSync.kt")
assert 'putString("theme", "grape")' not in overlay + account
assert 'if (doc.optBoolean("themeRefreshV1", false))' not in account
assert 'put("nativeTextStyle", it.toInt())' in overlay
assert 'onWriteSetting("general.native_text_style", floatArrayOf(it.toFloat()))' in overlay
assert 'it == 0.0 || it == 1.0' in overlay
assert 'if (!repository.hasSession || profile.id != owner) return false' in overlay
assert 'SettingsFocus.query = ""' in overlay
auth = read(base / "ui/CinematicAuthScreen.kt")
assert 'catch (_: kotlinx.coroutines.TimeoutCancellationException)' in auth
assert 'catch (cancelled: kotlinx.coroutines.CancellationException)' in auth
assert 'throw cancelled' in auth and 'authJob = null' in auth
assert 'withTimeout(30_000L) { bootstrap() }' in auth
hub = read(base / "ui/SettingsScreen.kt")
assert not any('else' in owner for owner in enclosing_if(hub, hub.index('title = "Log out"')))
print("PASS: Android legacy theme restore, shared text choice, stale-owner rejection and retryable auth")

def function(text, name):
    start = re.search(r'[^\n]*\b' + re.escape(name) + r'\([^;{}]*\)\s*\{', text).start()
    opening = text.index('{', start)
    depth, end = 1, opening + 1
    while depth:
        depth += (text[end] == '{') - (text[end] == '}')
        end += 1
    return text[start:end]

clang = Path(os.environ.get("LOCALAPPDATA", "")) / "Android/Sdk/ndk/28.2.13676358/toolchains/llvm/prebuilt/windows-x86_64/bin/clang.exe"
with tempfile.TemporaryDirectory(prefix="wyrm-session-text-") as temp:
    temp = Path(temp)
    # Only cglm's two plain vector typedefs are needed by this settings fixture.
    # The separate Android Clang syntax check uses the real cglm/ARM64 headers.
    (temp / "cglm").mkdir()
    (temp / "cglm/cglm.h").write_text("typedef float vec3[3]; typedef float vec4[4];\n")
    for label, engine in [("Android", ANDROID), ("generated iOS", ROOT / "build-original-source")]:
        header = read(engine / "app/src/game/user_settings.h")
        settings = read(engine / "app/src/game/user_settings.c")
        sheet = read(engine / "app/src/game/sheet_text.h")
        main = read(engine / "app/src/main.c")
        window = read(engine / "thermite/src/framework/twindow.c")
        resize = window[window.index('      bool changed ='):window.index('      break;', window.index('      bool changed ='))]
        legacy = re.search(r'typedef struct user_settings_ext \{[\s\S]*?\} user_settings_ext;', header)[0]
        legacy = legacy.replace('  int32_t native_text_style;\n', '').replace('user_settings_ext', 'legacy_ext')
        migration = settings[settings.index('    size_t text_at ='):settings.index('    size_t food_at =', settings.index('    size_t text_at ='))]
        policy = re.search(r'wyrm_high_visibility_text = android_home_near_original\(\) \|\|\s*usr->usrs.ext.native_text_style == 1;', main)[0]
        code = '#include "game/user_settings.h"\n' + legacy + r'''
_Static_assert(offsetof(user_settings_ext,native_text_style)==sizeof(legacy_ext), "new field overlaps legacy tail");
''' + function(settings, 'ext_take_int') + r'''
static bool wyrm_high_visibility_text=true, wyrm_sheet_warned=false;
static void* wyrm_sheet_set=(void*)1; static void* wyrm_text_normal=(void*)1; static void* wyrm_text_add=(void*)1;
static void SDL_Log(const char* x) {(void)x;}
''' + function(sheet, 'sheet_ok') + r'''
static bool original=false;
static bool android_home_near_original(void) {return original;}
typedef struct { bool surface_lost,swapchain_ok; } Context;
typedef struct { Context*ctx; } Env;
typedef struct { int size[2];bool _refresh; } Window;
static int resize_policy(int width,int height,int pending,int lost,int valid) {
 Context context={lost,valid};Env holder={&context};Env*env=&holder;
 Window win={{10,20},pending};Window*window=&win;
''' + resize + r'''
 return window->_refresh;
}
__attribute__((export_name("test"))) int test(void) {
 user_settings value={0};user_settings* settings=&value;user_settings_ext*ext=&value.ext;
 struct {user_settings usrs;} owner={0}; __typeof__(owner)*usr=&owner;
 size_t ext_at=offsetof(user_settings,ext); int fixed=0;
 for(int style=-1;style<=2;++style) for(int complete=0;complete<2;++complete) {
  ext->native_text_style=style;size_t written=complete?sizeof(*ext):sizeof(legacy_ext);
  size_t bytes_read=ext_at+written;
''' + migration + r'''
  int expected=complete&&(style==0||style==1)?style:1;
  if(ext->native_text_style!=expected)return 1;
 }
 for(int near=0;near<2;++near) for(int style=0;style<2;++style) {
  original=near;usr->usrs.ext.native_text_style=style;
''' + policy + r'''
  if(sheet_ok("Hello")!=(near||style))return 2;
  if(sheet_ok("")||sheet_ok((const char*)0)||sheet_ok("\xc3\xa9"))return 3;
 }
 wyrm_high_visibility_text=true;wyrm_sheet_set=0;
 if(sheet_ok("Fallback")||!wyrm_sheet_warned)return 4;
 if(resize_policy(10,20,0,0,1))return 5;
 if(!resize_policy(20,10,0,0,1))return 6;
 if(!resize_policy(10,20,1,0,1))return 7;
 if(!resize_policy(10,20,0,1,1))return 8;
 if(!resize_policy(10,20,0,0,0))return 9;
 return 0;
}
'''
        (temp / "test.c").write_text(code, encoding="utf-8")
        subprocess.run([str(clang), "--target=wasm32", "-O1", "-ffreestanding", "-nostdlib", "-Wl,--no-entry", "-I"+str(temp), "-I"+str(engine / "app/src"), str(temp / "test.c"), "-o", str(temp / "test.wasm")], check=True)
        subprocess.run(["node", "-e", "WebAssembly.instantiate(require('fs').readFileSync(process.argv[1])).then(({instance})=>{const r=instance.exports.test();if(r)throw Error('policy assertion '+r)})", str(temp / "test.wasm")], check=True)
        print(f"PASS: {label} actual C migration, append-only layout, Normal/High visibility, Near Original and fallback policy")
