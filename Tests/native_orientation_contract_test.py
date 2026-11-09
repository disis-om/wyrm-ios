"""Source contracts and actual C reducer/Rain geometry executed in Wasm.
No app/IPA build. UIKit/Swift app compilation and device behavior are separate.
"""
from pathlib import Path
import os
import plistlib
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
def read(path): return (ROOT / path).read_text(encoding="utf-8")
main = read("SourcesOriginal/Main.m")
host = read("SourcesOriginal/WyrmOrientationHost.inc")
keyboard = read("SourcesShell/WyrmKeyboard.swift")
lobby = read("SourcesShell/WyrmLobby.swift")
composer = read("SourcesShell/WyrmTeamHud.swift")
sync = read("SourcesShell/WyrmAccountSync.swift")
info = plistlib.loads((ROOT / "SourcesOriginal/Info.plist").read_bytes())
checks = {
    "plist allows portrait and both native landscape directions": set(info["UISupportedInterfaceOrientations"]) ==
        {"UIInterfaceOrientationPortrait", "UIInterfaceOrientationLandscapeLeft", "UIInterfaceOrientationLandscapeRight"},
    "SDL permits same orientations before initialization": 'SDL_SetHint(SDL_HINT_ORIENTATIONS, "Portrait LandscapeLeft LandscapeRight")' in main,
    "portrait root and full-screen game have native controller masks": "UIModalPresentationFullScreen" in host
        and "!internal_rotation ? UIInterfaceOrientationMaskLandscape : UIInterfaceOrientationMaskPortrait" in host,
    "iOS16 scene request and iOS15 preferred fullscreen presentation": "requestGeometryUpdateWithPreferences:" in host
        and "preferredInterfaceOrientationForPresentation" in host and "@available(iOS 16.0, *)" in host
        and 'forKey:@"orientation"' not in host,
    "serialized presentation uses actual portable reducer": "wyrm_orientation_action(" in host
        and "self.transitioning = YES" in host and "owner.current = target; owner.transitioning = NO" in host,
    "actual SDL/shell controller survives presentation": "[game adoptContent:self.content]" in host
        and "[self.home adoptContent:self.content]" in host and "SDL_DestroyWindow" not in host,
    "native surface stays identity; internal rotates its retained container only": "BOOL turn = self.landscape && internal_rotation" in host and "CGAffineTransformMakeRotation" in host and "CGAffineTransformMakeRotation" not in main
        and "rotationEffect(.degrees(90))" not in lobby and "surface.frame = bounds" in main,
    "stage reserves keyboard once in full logical canvas": "WyrmKeyboardGeometry.visibleHeight(outer.size.height, occlusion: keyboard.occlusion)" in lobby
        and '.ignoresSafeArea(engineOverlay ? .all : [], edges: .all)' in read("SourcesShell/WyrmDesignEntry.swift")
        and 'reader.scrollTo("lobby-name"' in lobby and "-118" not in lobby,
    "native keyboard observer stays independent from internal-only keys": "guard WyrmIOSInternalRotationActive() else { return wyrm_internalInputView() }" in read("SourcesShell/WyrmInternalKeyboard.swift") and "method_exchangeImplementations" not in keyboard
        and "class_addMethod" not in keyboard and "inputView(for" not in keyboard,
    "keyboard screen frame converted before window overlap": "window.convert(frame, from: screen.coordinateSpace)" in keyboard
        and "WyrmKeyboardGeometry.dockedOverlap" in keyboard,
    "native focus still suppresses Rain keyboard shortcuts": "!WyrmKeyboardController.shared.focused" in read("SourcesShell/WyrmRain.swift"),
    "composer contains native field and automatic keyboard avoidance": "WyrmKeyboardView" not in composer
        and "nativeComposer" in composer and "TextField(composer.global" in composer,
    "legacy standalone keyboard page stays removed": not (ROOT / "SourcesShell/WyrmKeyboardEmoji.swift").exists()
        and "WyrmKeyboardLookRows" not in read("SourcesShell/WyrmSettingsPages.swift")
        and 'id: "app.keyboard"' not in read("SourcesShell/WyrmSettingsSearch.swift"),
    "legacy account prefix kept and keyboard overlap transient": '("wyrm.ios.keyboard.", .sync)' in sync
        and "UserDefaults" not in keyboard and "WyrmIOSSetKeyboardOcclusion" in keyboard,
    "Rain uses direct window deltas and safe/keyboard bounded geometry": "CGFloat stageDX = dx" in main
        and "CGFloat stageDY = dy" in main and "wyrm_panel_geometry(stageWidth, stageHeight" in main
        and "MAX(safe.bottom, self.keyboardBottomInset)" in main,
    "keyboard dismissal restores unedited Rain offset": "c.rainOffset = c.rainOffsetBeforeKeyboard" in main
        and "!c.rainDraggedWithKeyboard" in main,
    "geometry success and all early deferrals have bounded follow-up": 'CACurrentMediaTime() + 20.0' in host
        and 'NSEC_PER_MSEC * 100' in host and 'owner.geometryRefreshQueued = NO' in host
        and all(f'deferGeometryRefresh:@"{reason}"' in host for reason in
                ['transitioning', 'pending-intent', 'host-detached', 'scene-inactive'])
        and 'sceneAccepted && boundsMatch' in host and 'self.geometryRequestSent = YES' in host,
    "native device observer returns before internal content mutation":
        '- (void)deviceTurned {\n  if (!internal_rotation) return;' in host
        and 'if (next == 2) wyrm_note_device_side();' in host
        and 'static int internal_turn = 1;' in host
        and 'internal_turn < 0 ? UIInterfaceOrientationLandscapeLeft : UIInterfaceOrientationLandscapeRight' in host,
    "internal option remains Developer-gated and cover maximum remains one second":
        'internalRotation && UserDefaults.standard.bool(forKey: Self.developerKey)' in read('SourcesShell/WyrmOrientation.swift')
        and 'now - self.coverRaisedAt > 1.0' in host
        and '[orientation_coordinator rearmGeometryObservation];' in main,
    "native CI polls strict scene and drawable geometry":
        'for i in $(seq 1 40); do' in read('.github/workflows/original-engine.yml')
        and 'python3 Scripts/check-native-lobby.py original-artifacts/lobby-stderr.log' in read('.github/workflows/original-engine.yml'),
}
for label, ok in checks.items(): print(f"{'PASS' if ok else 'FAIL'}: {label}")
assert all(checks.values()), "native orientation source contract failed"
print(f"Native orientation source contracts: {len(checks)}/{len(checks)} passed")

# Test the exact future-CI predicate, including the observed native failure.
import runpy
native_lobby_ready = runpy.run_path(str(ROOT/'Scripts/check-native-lobby.py'))['native_lobby_ready']
wide='Wyrm native orientation=game-landscape bounds=874x402 content=874x402\n'
internal='Wyrm native orientation=game-landscape bounds=402x874 content=874x402\n'
drawable='orientation=3 drawable=2622x1206\n'
assert native_lobby_ready('screen=LOBBY\n'+wide+drawable)
assert not native_lobby_ready('screen=LOBBY\n'+drawable), 'observed missing-native-log failure must remain red'
assert not native_lobby_ready('screen=LOBBY\n'+internal+drawable), 'internal geometry cannot prove native rotation'
assert not native_lobby_ready('screen=LOBBY\n'+wide+'drawable=1206x2622'), 'scene alone cannot prove drawable rotation'
assert not native_lobby_ready(wide+drawable), 'lobby screen is mandatory'
print('Native lobby smoke predicate: 5 positive/negative fixtures passed')

clang = Path(os.environ.get("LOCALAPPDATA", "")) / "Android/Sdk/ndk/28.2.13676358/toolchains/llvm/prebuilt/windows-x86_64/bin/clang.exe"
if clang.is_file():
    source = r'''
#include "WyrmOrientationPolicy.h"
#include "WyrmViewportGeometry.h"
static double output[6];
__attribute__((export_name("next"))) int next(int w,int c,int g,int busy,int active,int attached,int modal,int modern) {
 return wyrm_orientation_action(w,c,g,busy,active,attached,modal,modern);
}
__attribute__((export_name("fit"))) double* fit(double sw,double sh,double w,double h,double ox,double oy,double l,double t,double r,double b) {
 WyrmPanelGeometry p=wyrm_panel_geometry(sw,sh,w,h,ox,oy,l,t,r,b);
 output[0]=p.left;output[1]=p.top;output[2]=p.width;output[3]=p.height;output[4]=p.offset_x;output[5]=p.offset_y;return output;
}
'''
    script = r'''
const fs=require('fs'),assert=require('assert');
(async()=>{
 const {instance}=await WebAssembly.instantiate(fs.readFileSync(process.argv[2]),{}),x=instance.exports;
 let checks=0;function ok(value,why){assert(value,why);checks++}
 for(let w=0;w<3;w++)for(let c=0;c<3;c++)for(let g=0;g<2;g++)for(let a=0;a<2;a++)for(let m=0;m<2;m++){
  ok(x.next(w,c,g,1,1,a,m,1)===0,'in-flight transition never starts another operation');
  ok(x.next(w,c,g,0,0,a,m,1)===0,'background intent deferred until active');
 }
 ok(x.next(0,2,1,0,1,0,1,1)===2,'Back works while full-screen UIKit has detached the portrait root');
 ok(x.next(1,2,1,0,1,0,1,1)===3,'iOS16 changes game mask without moving the engine');
 ok(x.next(1,2,1,0,1,0,1,0)===2,'iOS15 re-presents preferred orientation using public fullscreen API');
 ok(x.next(2,0,0,0,1,1,1,1)===0,'other system modal defers Play');
 for(const modern of [0,1]){
  let wanted=0,current=0,game=0,busy=0,operation=null;
  function dispatch(){
   const action=x.next(wanted,current,game,busy,1,game?0:1,game?1:0,modern);
   if(action===1){ok(!game&&!busy,'only one live game host');game=1;busy=1;operation={action,target:wanted}}
   if(action===2){ok(game&&!busy,'return from owned game only');busy=1;operation={action}}
   if(action===3){current=wanted;ok(game&&!busy,'modern mask update keeps same host')}
  }
  function complete(){if(!operation)return;const old=operation;operation=null;busy=0;if(old.action===1)current=old.target;else{current=0;game=0}dispatch()}
  // Adversarial rapid Play/Back sequences while native presentations complete later.
  for(let n=0;n<3000;n++){wanted=(n*7+Math.floor(n/11))%3;dispatch();if(n%3===0)complete()}
  for(const target of [2,0,2,1,0]){wanted=target;dispatch();for(let n=0;n<5;n++)complete();ok(current===target&&game===(target>0?1:0)&&!busy,'latest target converges after queued transitions')}
 }
 const dims=[[375,667,0,20,0,0],[393,852,0,59,0,34],[667,375,44,0,44,21],[852,393,59,0,59,21]];
 for(const [sw,sh,l,t,r,safeBottom] of dims)for(const key of [0,160,216,260])for(const [w,h] of [[380,340],[299.6,271.6],[800,800]])for(const ox of [-2000,-100,-5,0,5,100,2000])for(const oy of [-2000,-100,-5,0,5,100,2000]){
  const b=Math.max(key,safeBottom),ptr=x.fit(sw,sh,w,h,ox,oy,l,t,r,b),v=[...new Float64Array(x.memory.buffer,ptr,6)];
  ok(v.every(Number.isFinite),'finite native panel geometry');
  ok(v[0]>=l-1e-7&&v[1]>=t-1e-7&&v[0]+v[2]<=sw-r+1e-7&&v[1]+v[3]<=sh-b+1e-7,'panel stays within native notch and keyboard bounds');
  ok(Math.abs(v[2]/v[3]-w/h)<1e-7,'panel aspect preserved');
 }
 let a=[...new Float64Array(x.memory.buffer,x.fit(852,393,200,120,0,0,59,0,59,21),6)];
 let b=[...new Float64Array(x.memory.buffer,x.fit(852,393,200,120,5,9,59,0,59,21),6)];
 ok(b[0]-a[0]===5&&b[1]-a[1]===9,'native drag uses dx/dy directly, no inverse quarter turn');
 // The old CI target ignored landscape safe areas and failed on move zero.
 for(const [sw,sh,l,t,r,bottom] of [[874,402,62,0,62,21],[852,393,59,0,59,21],[393,852,0,59,0,34]]) {
  const fit=(ox,oy)=>[...new Float64Array(x.memory.buffer,x.fit(sw,sh,299.6,271.6,ox,oy,l,t,r,bottom),6)];
  let state=fit(0,0);
  if(l>0){const oldX=(sw-state[2])*.059;ok(oldX<l,'old move-zero target enters notch');}
  for(let move=0;move<100;move++){
   const targetX=l+Math.max(0,sw-r-state[2]-l)*(.05+.9*(move+1)/100);
   const targetY=t+Math.max(0,sh-bottom-state[3]-t)*(.1+.8*(move+1)/100);
   state=fit(state[4]+targetX-state[0],state[5]+targetY-state[1]);
   const repeat=fit(state[4],state[5]);
   ok(Math.abs(state[0]-targetX)<.01&&Math.abs(state[1]-targetY)<.01,'100 safe-area smoke destinations are reached');
   ok(repeat.every((v,i)=>Math.abs(v-state[i])<1e-7),'repeated native layout holds the dragged position');
  }
 }
 const bad=[...new Float64Array(x.memory.buffer,x.fit(NaN,393,200,120,Infinity,0,0,0,0,0),6)];
 ok(bad.every(Number.isFinite),'invalid viewport input remains bounded');
 console.log(`Native orientation/Rain C: ${checks} checks passed (rapid transitions, iOS15/16 policy, notch/keyboard bounds, direct drag)`);
})().catch(e=>{console.error(e);process.exit(1)});
'''
    with tempfile.TemporaryDirectory(prefix="wyrm-orientation-") as temp:
        temp = Path(temp)
        (temp / "geometry.c").write_text(source, encoding="utf-8")
        (temp / "check.cjs").write_text(script, encoding="utf-8")
        subprocess.run([str(clang), "--target=wasm32", "-nostdlib", "-O1", "-ffreestanding",
                        "-Wl,--no-entry", "-Wl,--export-dynamic", "-I", str(ROOT / "SourcesOriginal"),
                        "-o", str(temp / "geometry.wasm"), str(temp / "geometry.c")], check=True)
        subprocess.run(["node", str(temp / "check.cjs"), str(temp / "geometry.wasm")], check=True)
else:
    print("Portable C/Wasm execution skipped: configured Windows Clang unavailable")

swift = shutil.which("swiftc")
if swift:
    with tempfile.TemporaryDirectory(prefix="wyrm-native-keys-") as temp:
        output = Path(temp) / "geometry"
        subprocess.run([swift, str(ROOT / "SourcesShell/WyrmKeyboardGeometry.swift"),
                        str(ROOT / "Tests/native_keyboard_geometry_check.swift"), "-o", str(output)], check=True)
        subprocess.run([str(output)], check=True)
else:
    print("Swift keyboard fixture execution skipped: swiftc unavailable")
