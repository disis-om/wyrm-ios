"""Execute production Classic/release/tap C functions in Wasm; no device claims."""
from pathlib import Path
import os, shutil, subprocess, tempfile
ROOT=Path(__file__).resolve().parents[1]
engine = ROOT.parent/'Wyrm Android/app/src'
if not engine.exists(): engine=ROOT/'build-original-source/app/src'
source=(engine/'mobile/mobile_controls.c').read_text(encoding='utf-8')
def function(name):
    start=source.index('static ',source.index(name)-32)
    end=source.index('{',start); depth=1; cursor=end+1
    while depth:
        if source[cursor]=='{': depth+=1
        elif source[cursor]=='}': depth-=1
        cursor+=1
    return source[start:cursor]
code=r'''
void* memset(void* p,int c,__SIZE_TYPE__ n){volatile unsigned char* b=p;while(n--)*b++=(unsigned char)c;return p;}
typedef unsigned long long uint64_t;
typedef uint64_t Uint64;
typedef int bool;
#define true 1
#define false 0
#define SDL_EVENT_FINGER_DOWN 1
#define SDL_EVENT_FINGER_UP 2
#define SDL_EVENT_FINGER_CANCELED 3
#define SDL_EVENT_FINGER_MOTION 4
#define MOBILE_BOOST_FIXED 1
typedef struct {int type;} SDL_Event;
typedef struct { bool joystick_down,boost_down,zoom_down,aim_valid; uint64_t joystick_finger,boost_finger,zoom_finger; float joystick_axis[2],boost_origin[2]; } mobile_controls_state;
typedef struct {float boost_x,boost_y,boost_size; int boost_mode;} mobile_control_settings;
typedef struct {mobile_controls_state mobile_controls; struct {mobile_control_settings mobile_controls;} usrs;} user;
typedef struct {int size[2];} window;
typedef struct {window* wnd;user* usr;} tenv;
static struct {uint64_t id;float x,y;bool down,ignored;} classic_fingers[16];
static bool arrow_tap_boost;
static bool arrow_last_tap_released,boost_secondary;
static bool boost_steering_promoted;
static float boost_motion_total,boost_motion_last[2];
static uint64_t arrow_last_down_finger;
static uint64_t classic_boost_finger,arrow_last_down_ms,clock_ms;
static float arrow_last_down[2];
static bool original;
static Uint64 SDL_GetTicks(void){return clock_ms;}
static float fabsf(float a){return a<0?-a:a;}
static float sqrtf(float a){float x=a>1?a:1;for(int i=0;i<30;++i)x=(x+a/x)*.5f;return x;}
static float original_unit(tenv*e){return 1;}
static float control_scale(tenv*e){return 1;}
static bool android_home_near_original(void){return original;}
static void original_boost_centre(tenv*e,float*x,float*y){*x=950;*y=450;}
static void normalized_position(tenv*e,float x,float y,float*ox,float*oy){*ox=x*e->wnd->size[0];*oy=y*e->wnd->size[1];}
static bool inside_circle(float x,float y,float bx,float by,float r){return (x-bx)*(x-bx)+(y-by)*(y-by)<=r*r;}
static bool inside_zoom(tenv*e,float x,float y){return false;}
static void set_zoom_from_touch(tenv*e,float x,float y){}
'''
for name in ['arrow_note_down(', 'release_owned_touch(', 'take_boost(', 'classic_touch(']: code+='\n'+function(name)+'\n'
aim_start=source.index('bool mobile_controls_classic_aim(')
aim_body=source.index('{',aim_start); depth=1; end=aim_body+1
while depth:
    if source[end]=='{':depth+=1
    elif source[end]=='}':depth-=1
    end+=1
code+='\n#define MOBILE_STEERING_CLASSIC 3\nstatic int mobile_controls_steering_mode(tenv* e){return 3;}\n'+source[aim_start:end]+'\n'
code+=r'''
#define CHECK(c) do {if(!(c)) return __LINE__;}while(0)
__attribute__((export_name("test"))) int test(void){
 user u={0};window w={{1000,500}};tenv e={&w,&u};SDL_Event event={SDL_EVENT_FINGER_DOWN};
 original=true;clock_ms=1000;CHECK(classic_touch(&e,&event,11,750,250));CHECK(u.mobile_controls.aim_valid);
 float ax=0,ay=0;CHECK(mobile_controls_classic_aim(&e,&ax,&ay));CHECK(ax==750&&ay==250);
 CHECK(fabsf(u.mobile_controls.joystick_axis[0]-1)<.001f);CHECK(!arrow_tap_boost);
 clock_ms=2000;classic_touch(&e,&event,22,750,350);
 CHECK(mobile_controls_classic_aim(&e,&ax,&ay));CHECK(ax==750&&ay==300);
 CHECK(fabsf(u.mobile_controls.joystick_axis[0]-.9805807f)<.001f);
 CHECK(fabsf(u.mobile_controls.joystick_axis[1]-.1961161f)<.001f);
 event.type=SDL_EVENT_FINGER_DOWN;classic_touch(&e,&event,23,100,100);
 CHECK(mobile_controls_classic_aim(&e,&ax,&ay));CHECK(ax==750&&ay==300);
 CHECK(fabsf(u.mobile_controls.joystick_axis[0]-.9805807f)<.001f);
 event.type=SDL_EVENT_FINGER_CANCELED;classic_touch(&e,&event,23,100,100);
 event.type=SDL_EVENT_FINGER_UP;classic_touch(&e,&event,11,750,250);
 CHECK(fabsf(u.mobile_controls.joystick_axis[1]-.3713907f)<.001f);
 event.type=SDL_EVENT_FINGER_CANCELED;classic_touch(&e,&event,22,750,350);
 for(int i=0;i<16;++i)CHECK(!classic_fingers[i].down);
 CHECK(!mobile_controls_classic_aim(&e,&ax,&ay));
 event.type=SDL_EVENT_FINGER_DOWN;clock_ms=3000;classic_touch(&e,&event,33,250,250);
 event.type=SDL_EVENT_FINGER_UP;classic_touch(&e,&event,33,250,250);
 event.type=SDL_EVENT_FINGER_DOWN;clock_ms=3200;classic_touch(&e,&event,44,260,250);
 CHECK(arrow_tap_boost && classic_boost_finger==44);
 event.type=SDL_EVENT_FINGER_CANCELED;classic_touch(&e,&event,44,260,250);CHECK(!arrow_tap_boost);
 u.mobile_controls.boost_down=true;u.mobile_controls.boost_finger=77;
 u.mobile_controls.zoom_down=true;u.mobile_controls.zoom_finger=88;
 u.mobile_controls.joystick_down=true;u.mobile_controls.joystick_finger=99;arrow_tap_boost=true;
 release_owned_touch(&u.mobile_controls,123);CHECK(u.mobile_controls.boost_down && u.mobile_controls.zoom_down);
 release_owned_touch(&u.mobile_controls,77);CHECK(!u.mobile_controls.boost_down && u.mobile_controls.zoom_down && u.mobile_controls.joystick_down);
 release_owned_touch(&u.mobile_controls,99);CHECK(!u.mobile_controls.joystick_down && !arrow_tap_boost && u.mobile_controls.zoom_down);
 release_owned_touch(&u.mobile_controls,88);CHECK(!u.mobile_controls.zoom_down);
 original=true;event.type=SDL_EVENT_FINGER_DOWN;classic_touch(&e,&event,55,900,400);
 CHECK(u.mobile_controls.boost_down && u.mobile_controls.boost_finger==55);
 release_owned_touch(&u.mobile_controls,55);CHECK(!u.mobile_controls.boost_down);
 original=false;event.type=SDL_EVENT_FINGER_DOWN;
 classic_touch(&e,&event,101,750,250);
 classic_touch(&e,&event,102,100,100);
 CHECK(mobile_controls_classic_aim(&e,&ax,&ay));CHECK(ax==750&&ay==250);
 event.type=SDL_EVENT_FINGER_UP;classic_touch(&e,&event,101,750,250);
 CHECK(mobile_controls_classic_aim(&e,&ax,&ay));CHECK(ax==100&&ay==100);
 event.type=SDL_EVENT_FINGER_CANCELED;classic_touch(&e,&event,102,100,100);
 CHECK(!mobile_controls_classic_aim(&e,&ax,&ay));CHECK(!arrow_tap_boost);
 return 0;
}
'''
clang=Path(os.environ.get('LOCALAPPDATA',''))/'Android/Sdk/ndk/28.2.13676358/toolchains/llvm/prebuilt/windows-x86_64/bin/clang.exe'
with tempfile.TemporaryDirectory() as tmp:
    p=Path(tmp)
    if clang.exists():
        (p/'test.c').write_text(code)
        subprocess.run([str(clang),'--target=wasm32','-nostdlib','-Wl,--no-entry','-Wl,--export-memory','-O2',str(p/'test.c'),'-o',str(p/'test.wasm')],check=True)
        subprocess.run(['node','-e',"WebAssembly.instantiate(require('fs').readFileSync(process.argv[1]),{}).then(({instance})=>{const r=instance.exports.test();if(r)throw Error('C assertion at line '+r);console.log('Production Classic/release C passed')})",str(p/'test.wasm')],check=True)
    else:
        native=code.replace('__attribute__((export_name("test")))','')+'\nint main(void){return test();}\n'
        (p/'test.c').write_text(native)
        subprocess.run([shutil.which('clang') or 'cc','-O2',str(p/'test.c'),'-o',str(p/'test')],check=True)
        subprocess.run([str(p/'test')],check=True)
        print('Production Classic/release C passed (native host)')
assert '(usrs->hotkeys[HOTKEY_BOT].active && gdata->bot.output.accel)' in (engine/'game/input.c').read_text()
assert source.index('release_owned_touch(state, finger);') < source.index('if (android_team_hud_touch')
print('Bot boost gated; pointer release precedes panel routing')
