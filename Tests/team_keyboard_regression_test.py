"""Source contracts + actual native presence/cosmetic and Kotlin delivery fixtures.
No APK/IPA build, device operation or live team message is performed.
"""
from pathlib import Path
import json
import os
import re
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
ANDROID = ROOT.parent / "Wyrm Android"
def read(p): return p.read_text(encoding="utf-8")
def body(source, anchor):
    start = source.index(anchor)
    opening = source.index("{", start)
    depth = 0
    for i in range(opening, len(source)):
        depth += (source[i] == "{") - (source[i] == "}")
        if not depth: return source[start:i+1]
    raise AssertionError(anchor)

team = read(ROOT / "SourcesShell/WyrmTeam.swift")
keys = read(ROOT / "SourcesShell/WyrmKeyboard.swift")
internal = read(ROOT / "SourcesShell/WyrmInternalKeyboard.swift")
routes = read(ROOT / "SourcesShell/WyrmDesignMain.swift")
composer = read(ROOT / "SourcesShell/WyrmTeamHud.swift")
lobby = read(ROOT / "SourcesShell/WyrmLobby.swift")
assert 'private let clientIdentity = String(UUID()' in team
assert 'value: "WYRMPLYR" + presence.nickname' not in team
assert 'guard !Self.ntlServicesDisabled, !pollInFlight' in team
assert 'generation == pollGeneration, !Task.isCancelled' in team
assert 'let outgoing = messageAttempted ? "" : pending' in team
assert 'String(Self.string(row["nick"]).prefix(8)) == clientIdentity' in team
assert 'pendingPolls >= 3' in team and 'failedDraft = pending' in team
assert 'replacingOccurrences(of: "+", with: "%2B")' in team
assert 'URLQueryItem(name: "msg", value: Self.wireMessage(outgoing))' in team
assert 'Self.messageLines(Self.string(row["msg"])).contains(pending)' in team
assert 'request.setValue("http://slither.io/", forHTTPHeaderField: "Referer")' in team
assert 'guard team.send(composer.draft) else { return }' in composer
assert 'if team.send(message) { message = "" }' in read(ROOT / "SourcesShell/WyrmDesignDetails.swift")
for anchor in ['private func open(', 'private func pop(']:
    assert 'WyrmKeyboardController.shared.dismiss()' in body(routes, anchor)
for anchor in ['func close()', 'func closeNow()']:
    assert 'WyrmKeyboardController.shared.dismiss()' in body(composer, anchor)
assert 'dismissing = true' in keys and '|| dismissing' in keys
assert 'value.translation.height > 36' in keys and 'abs(value.translation.width) * 1.5' in keys
for p in ['WyrmChatUI.swift', 'WyrmDiscordChat.swift']:
    assert 'content.modifier(WyrmDismissKeyboardOnScroll())' in read(ROOT / 'SourcesShell' / p)
assert 'canvasHeight: proxy.size.height' in internal and 'canvasHeight.map' in keys
assert 'visibleHeight(outer.size.height, occlusion: keyboard.occlusion)' in lobby
assert '.background(wyrmScopedColours.paper.ignoresSafeArea())' in lobby
assert '.frame(width: width, height: height)' in internal and '.position(x: proxy.size.width / 2 + dx' in internal
assert 'let occupied = height + 6 - dy' in internal
hud = read(ROOT / 'SourcesShell/WyrmTeamHud.swift')
assert '.padding(.bottom, keyboard.occlusion)' in hud and '.modifier(WyrmAboveKeys())' not in hud
assert '.ignoresSafeArea(engineOverlay ? .all : [], edges: .all)' in read(ROOT / 'SourcesShell/WyrmDesignEntry.swift')
print('PASS: iOS session identity, serialized delivery, ownership, retained draft and keyboard lifecycle contracts')

if ANDROID.exists():
    base = ANDROID / 'android/app/src/main/java/com/wyrm/omrajput'
    overlay = read(base / 'ui/WyrmOverlay.kt')
    service = read(base / 'data/TeamService.kt')
    assert 'clientIdentity: String = java.util.UUID.randomUUID()' in service
    assert 'escapeMessages: Boolean = true' in service
    assert 'team.poll(presence, outgoing, pending, owner)' in overlay
    assert 'pending?.takeUnless { teamSendAttempted }' in overlay
    assert 'if (failure is kotlinx.coroutines.CancellationException) throw failure' in overlay
    assert 'if (global != arenaChatGlobal) teamDraft = ""' in overlay
    assert 'if (routeState != value) dismissEditing()' in overlay
    assert 'if (panelOpenState && !value) dismissEditing()' in overlay
    assert 'focusManager.clearFocus(force = true)' in overlay
    print('PASS: Android queue, session ownership, channel separation and immediate navigation/IME dismissal contracts')

    # Execute the app's actual Kotlin send/request/response/reset bodies on JVM.
    # Only UI/network boundaries are stubbed; no Android app or Gradle invocation.
    jdk = Path('C:/Program Files/Android/Android Studio/jbr/bin')
    cache = Path.home() / '.gradle/caches/modules-2/files-2.1'
    dependencies = []
    for relative in ['org.jetbrains.kotlin/kotlin-compiler-embeddable/2.3.21',
                     'org.jetbrains.kotlin/kotlin-stdlib/2.3.21',
                     'org.jetbrains.kotlin/kotlin-script-runtime/2.3.21',
                     'org.jetbrains.kotlinx/kotlinx-coroutines-core-jvm/1.10.2',
                     'org.jetbrains/annotations/26.1.0']:
        dependencies += list((cache / relative).rglob('*.jar'))
    dependencies += list((cache / 'org.jetbrains.kotlin/kotlin-reflect').rglob('*.jar'))[:1]
    if (jdk/'java.exe').exists() and len(dependencies) >= 4:
        request = overlay[overlay.index('                    val pending = teamOutbox'):]
        request = request[:request.index('                    val next = try')]
        response = body(overlay, 'if (pending != null && teamOutbox == pending)')
        encoder = service[service.index('    private fun wireMessage('):].split('\n\n', 1)[0]
        fixture = '''
enum class Route { TEAM, ARENA_CHAT }
data class TeamState(val status: String="",val messageAcknowledged: Boolean=false)
class Team(var configured:Boolean=true)
class Host { fun onWriteTeamMembers(value:String) {} }
class Delivery {
 var activity=Any();var route=Route.TEAM;var arenaChatGlobal=false
 var teamDraft="";var teamOutbox:String?=null;var teamSending=false
 var teamSendAttempted=false;var teamPendingPolls=0;var failedTeamDraft=""
 var teamState=TeamState();var team=Team();var teamEnabled=true;var teamSelectionEpoch=0
 var packedTeamSnapshot="";var host:Host?=null
 fun startTeamPolling() {}
 fun send(text:String) { teamDraft=text;sendTeamMessage() }
 fun request():String? {
''' + request + '''
 return outgoing
 }
 fun response(next:TeamState,pending:String?=teamOutbox) {
''' + response + '\n}\n' + body(overlay, 'private fun sendTeamMessage()') + '\n' + body(overlay, 'private fun clearPackedTeam()').replace('private fun','fun',1) + '\n' + encoder + '''
 fun encode(value:String)=wireMessage(value)
}
fun main() {
 var checks=0
 fun ok(value:Boolean) {check(value);checks++}
 val x=Delivery()
 x.send(" hello + दुनिया ");ok(x.teamSending);ok(x.teamDraft=="")
 ok(x.request()=="hello + दुनिया");ok(x.teamOutbox=="hello + दुनिया");ok(x.request()==null)
 x.response(TeamState(messageAcknowledged=true));ok(!x.teamSending);ok(x.teamOutbox==null)
 x.send("first");x.request();x.send("second");ok(x.teamOutbox=="first")
 x.response(TeamState());ok(x.teamSending);ok(x.request()==null)
 x.response(TeamState());ok(x.teamSending);x.response(TeamState());ok(!x.teamSending)
 ok(x.failedTeamDraft=="first");ok(x.teamDraft=="second");ok(x.teamOutbox==null)
 x.clearPackedTeam();ok(x.failedTeamDraft=="");ok(x.teamSelectionEpoch==1)
 x.send("private");x.request();x.route=Route.ARENA_CHAT;x.arenaChatGlobal=true;x.teamDraft="global"
 repeat(3){x.response(TeamState())};ok(x.teamDraft=="global");ok(x.failedTeamDraft=="private")
 x.clearPackedTeam();x.team.configured=false;x.send("kept");ok(!x.teamSending);ok(x.teamDraft=="kept")
 x.team.configured=true;x.send("  \n ");ok(!x.teamSending)
 x.send("a".repeat(281));ok(!x.teamSending)
 x.send("one\\ntwo");ok(x.teamOutbox=="one two")
 ok(x.encode("a & <b> + 👋")=="a&nbsp;&amp;&nbsp;&lt;b&gt;&nbsp;+&nbsp;👋")
 ok(x.encode("<br>")=="&lt;br&gt;");ok(x.encode("&nbsp;")=="&amp;nbsp;")
 ok(java.net.URLEncoder.encode(x.encode("a+b"),"UTF-8")=="a%2Bb")
 println("Actual Kotlin delivery: $checks assertions passed")
}
'''
        # The above Python triple literal needs a Kotlin escaped newline.
        fixture = fixture.replace('x.send("  \n ")', 'x.send("  \\n ")')
        stub = 'package android.widget\nobject Toast {const val LENGTH_LONG=1;fun makeText(a:Any,b:String,c:Int)=this;fun show(){}}\n'
        cp = os.pathsep.join(map(str, dependencies))
        stdlib = next(p for p in dependencies if p.name.startswith('kotlin-stdlib-'))
        with tempfile.TemporaryDirectory(prefix='wyrm-team-delivery-') as tmp:
            tmp=Path(tmp);(tmp/'Delivery.kt').write_text(fixture,encoding='utf-8');(tmp/'Toast.kt').write_text(stub)
            subprocess.run([str(jdk/'java.exe'),'-Xmx384m','-cp',cp,'org.jetbrains.kotlin.cli.jvm.K2JVMCompiler',
                '-no-stdlib','-no-reflect','-jvm-target','17','-classpath',str(stdlib),'-d',str(tmp/'test.jar'),
                str(tmp/'Delivery.kt'),str(tmp/'Toast.kt')],check=True)
            subprocess.run([str(jdk/'java.exe'),'-cp',str(tmp/'test.jar')+os.pathsep+str(stdlib),'DeliveryKt'],check=True)
    else:
        print('SKIP: actual Kotlin JVM fixture needs cached Kotlin compiler/JDK')

ndk = Path.home() / 'AppData/Local/Android/Sdk/ndk/28.2.13676358/toolchains/llvm/prebuilt/windows-x86_64/bin/clang.exe'
trees = ([ANDROID] if ANDROID.exists() else []) + [ROOT / 'build-original-source']
for tree in trees:
    setup = read(tree / 'app/src/imgui_setup.c')
    assert '.PipelineCache = VK_NULL_HANDLE' in setup
    assert 'igImplVulkan_RenderDrawData(igGetDrawData(), cmd, VK_NULL_HANDLE)' in setup
    for renderer in ['bd', 'bg', 'bp', 'bst', 'fd', 'mm', 'spr']:
        assert 'ctx->device, NULL, 1,' not in read(tree / f'app/src/rendering/{renderer}_renderer.c')
    presence = body(read(tree / 'app/src/platform/android_team.c'), 'void android_team_poll(tenv* env)')
    redraw = read(tree / 'app/src/game/redraw.c')
    expression = re.search(r'const int hide_cosmetics =\s*(.*?);', redraw, re.S).group(1)
    assert 'if (!hide_cosmetics && mode->show_accessories' in redraw
    assert 'if (!hide_cosmetics && o->id == gdata->data.snake_id)' in redraw
    assert 'if (!hide_cosmetics)\n          tags_draw' in redraw
    if not ndk.exists():
        print('SKIP: native Wasm fixture needs configured NDK clang'); continue
    source = r'''
#include <stddef.h>
#include <stdbool.h>
#include <stdarg.h>
typedef unsigned long long Uint64;
typedef struct { int id, ntl_id; float xx, yy, fx, fy; } snake;
typedef struct { int conn, curr_screen; struct { snake *snakes; int snake_id, score, rank; } data; } game_data;
typedef struct { char nickname[32]; int tag_index, accessory; struct {int active;} hotkeys[1]; struct {int assist_hide_cosmetics;} ext; } user_settings;
typedef struct { game_data gdata; user_settings usrs; } tuser_data;
typedef struct { tuser_data *usr; } tenv;
#define CONNECTED 1
#define PLAYING 2
#define HOTKEY_BOT 0
#define HOTKEY_ASSIST 0
#define PRESENCE_PUBLISH_MS 250
static int count, output_x, output_y, output_sid, output_score;
#define tdarray_length(x) count
static void *team_mutex = (void*)1;
static char presence[256];
static Uint64 presence_published_at;
static bool presence_was_playing;
static Uint64 clock;
static Uint64 SDL_GetTicks(void) { return clock += 1000; }
static void SDL_LockMutex(void *p) {(void)p;}
static void SDL_UnlockMutex(void *p) {(void)p;}
static int tags_ntl_id(int value) {return value;}
static const char *user_settings_arena(user_settings *s) {(void)s;return "test:444";}
void *memcpy(void *d,const void *s,size_t n) { for(size_t i=0;i<n;i++) ((char*)d)[i]=((const char*)s)[i];return d; }
void *memset(void *d,int v,size_t n) { for(size_t i=0;i<n;i++) ((char*)d)[i]=(char)v;return d; }
static int snprintf(char *d,size_t n,const char *f,...) {
 for(size_t i=0;i<n;i++)d[i]=0;
 va_list v;va_start(v,f);(void)va_arg(v,char*);output_score=va_arg(v,int);
 output_x=va_arg(v,int);output_y=va_arg(v,int);(void)va_arg(v,int);(void)va_arg(v,char*);
 (void)va_arg(v,int);output_sid=va_arg(v,int);va_end(v);return 0;
}
''' + presence + r'''
int scenario(int index,int connected,int playing) {
 snake snakes[3]={{1,10,100,200,0,0},{2,20,300,400,0,0},{3,30,500,600,0,0}};
 tuser_data usr={0};usr.gdata.conn=connected;usr.gdata.curr_screen=playing;
 usr.gdata.data.snakes=snakes;usr.gdata.data.snake_id=index+1;usr.gdata.data.score=700;count=index==4?0:3;
 tenv env={&usr};android_team_poll(&env);return output_sid;
}
int x(void){return output_x;} int y(void){return output_y;} int score(void){return output_score;}
int hidden(int assist,int toggle) {user_settings value={0};value.hotkeys[0].active=assist;value.ext.assist_hide_cosmetics=toggle;user_settings *usrs=&value;
 return ''' + expression + r'''; }
'''
    script = r'''
const fs=require('fs'),a=require('assert');(async()=>{
 const {instance}=await WebAssembly.instantiate(fs.readFileSync(process.argv[2]),{}),e=instance.exports;let checks=0;
 const ok=(v)=>{a(v);checks++};
 for(let i=0;i<3;i++){ok(e.scenario(i,1,2)===(i+1)*10);ok(e.x()===100+i*200);ok(e.y()===200+i*200);ok(e.score()===700);}
 ok(e.scenario(3,1,2)===0);ok(e.x()===0);ok(e.y()===0);
 ok(e.scenario(4,1,2)===0);ok(e.scenario(1,0,2)===0);ok(e.score()===0);ok(e.scenario(1,1,0)===0);
 for(let assist=0;assist<2;assist++)for(let toggle=0;toggle<2;toggle++)ok(e.hidden(assist,toggle)===(assist&&toggle?1:0));
 console.log(`Actual native presence/cosmetic fixture: ${checks} assertions passed`);
})().catch(e=>{console.error(e);process.exit(1)});
'''
    with tempfile.TemporaryDirectory(prefix='wyrm-team-keys-') as tmp:
        tmp = Path(tmp); (tmp/'fixture.c').write_text(source); (tmp/'check.cjs').write_text(script)
        subprocess.run([str(ndk),'--target=wasm32','-nostdlib','-ffreestanding','-fno-builtin','-O1',
                        '-Wl,--no-entry','-Wl,--export-all',str(tmp/'fixture.c'),'-o',str(tmp/'fixture.wasm')],check=True)
        subprocess.run(['node',str(tmp/'check.cjs'),str(tmp/'fixture.wasm')],check=True)
    print('PASS:', tree.name, 'actual C local-snake lookup and Assist visibility')
