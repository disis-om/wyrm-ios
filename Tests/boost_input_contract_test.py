"""Execute production touch ownership and boost policy; no phone claims."""
from pathlib import Path
import os,subprocess,tempfile,shutil,re
ROOT=Path(__file__).resolve().parents[1]
engine=ROOT.parent/'Wyrm Android/app/src'
if not engine.exists():engine=ROOT/'build-original-source/app/src'
if os.environ.get('WYRM_TEST_ENGINE'):engine=Path(os.environ['WYRM_TEST_ENGINE'])
source=(engine/'mobile/mobile_controls.c').read_text(encoding='utf-8')
def fn(name):
 start=re.search(r'^(?:static )?(?:bool|void) '+re.escape(name),source,re.M).start()
 pos=source.index('{',start);depth=1;end=pos+1
 while depth:
  if source[end]=='{':depth+=1
  if source[end]=='}':depth-=1
  end+=1
 return source[start:end].replace('WYRM_MOBILE','WYRM_SDL_JNI')
code=r'''
#define WYRM_SDL_JNI 1
#define true 1
#define false 0
#define MOBILE_EDIT_NONE 0
#define MOBILE_JOYSTICK_DYNAMIC 0
#define MOBILE_JOYSTICK_FIXED 1
#define MOBILE_STEERING_ARROW 2
#define MOBILE_STEERING_CLASSIC 3
#define MOBILE_LEFT_HANDED 0
#define MOBILE_BOOST_FIXED 1
#define SDL_EVENT_FINGER_UP 2
#define SDL_EVENT_FINGER_CANCELED 3
#define SDL_EVENT_FINGER_DOWN 1
#define SDL_EVENT_FINGER_MOTION 4
typedef int bool;
typedef struct {int type;} SDL_Event;
typedef unsigned int uint32_t;
typedef unsigned long long uint64_t;
typedef uint64_t Uint64;
void* memset(void*p,int c,__SIZE_TYPE__ n){volatile unsigned char*b=p;while(n--)*b++=c;return p;}
typedef struct {bool joystick_down,boost_down,zoom_down,edit_down,ui_scroll_down,aim_valid;uint64_t joystick_finger,boost_finger,zoom_finger;float boost_origin[2],joystick_origin[2],joystick_axis[2],arrow_drag_distance;int edit_target;} mobile_controls_state;
typedef struct {float joystick_x,joystick_y,boost_x,boost_y,joystick_size,boost_size;int boost_mode,handedness;} mobile_control_settings;
typedef struct {mobile_controls_state mobile_controls;struct{struct{int vfrb;}data;}gdata;struct {mobile_control_settings mobile_controls;struct{bool arrow_double_tap_boost;}ext;}usrs;} user;
typedef struct {int size[2];} window;
typedef struct {window*wnd;user*usr;} tenv;
static struct{uint64_t id;float x,y;bool down,ignored;} classic_fingers[16];
static bool arrow_tap_boost,arrow_last_tap_released,boost_secondary,original;
static bool boost_steering_promoted;
static float boost_motion_total,boost_motion_last[2];
static uint64_t arrow_last_down_ms,arrow_last_down_finger,classic_boost_finger,clock_ms;
static float arrow_last_down[2];
static int mode;
static Uint64 SDL_GetTicks(void){return clock_ms;}
static float fabsf(float x){return x<0?-x:x;}
static float original_unit(tenv*e){return 1;}
static float control_scale(tenv*e){return 1;}
static bool android_home_near_original(void){return original;}
static int mobile_controls_steering_mode(tenv*e){return mode;}
static bool wyrm_arrow_mode(tenv*e){return !original&&mode==2;}
static void normalized_position(tenv*e,float x,float y,float*a,float*b){*a=x*e->wnd->size[0];*b=y*e->wnd->size[1];}
static bool inside_circle(float x,float y,float a,float b,float r){return (x-a)*(x-a)+(y-b)*(y-b)<=r*r;}
static bool inside_zoom(tenv*e,float x,float y){return false;}
static void set_zoom_from_touch(tenv*e,float x,float y){}
static void arrow_seed(tenv*e,float x,float y){e->usr->mobile_controls.aim_valid=true;}
static int arrow_moves;
static void update_arrow(tenv*e,float x,float y){++arrow_moves;}
static void update_joystick(tenv*e,float x,float y){e->usr->mobile_controls.aim_valid=true;}
static void original_boost_centre(tenv*e,float*x,float*y){*x=e->usr->usrs.mobile_controls.boost_x*e->wnd->size[0];*y=e->usr->usrs.mobile_controls.boost_y*e->wnd->size[1];}
static void original_joystick_centre(tenv*e,float*x,float*y){*x=e->usr->usrs.mobile_controls.joystick_x*e->wnd->size[0];*y=350;}
static void original_aim(tenv*e,float x,float y){e->usr->mobile_controls.aim_valid=true;}
static bool knob_follows_snake(void){return false;}
static bool joystick_heading(tenv*e,float*x,float*y){return false;}
'''
for name in ['arrow_note_down(', 'reset_touches(', 'sync_touch_policy(', 'release_owned_touch(', 'take_boost(', 'touch_is_owned(', 'reclaim_arrow_steering(', 'original_touch(', 'finish_touch(', 'wyrm_touch_down(', 'track_boost_motion(', 'decay_boost_motion(', 'mobile_controls_boost_down(']:code+='\n'+fn(name)+'\n'
settings=(engine/'game/user_settings.c').read_text(encoding='utf-8')
migration=settings[settings.index('    size_t tap_at ='):settings.index('    size_t text_at =',settings.index('    size_t tap_at ='))]
code+=r'''
typedef __SIZE_TYPE__ size_t;
#define offsetof(t,m) __builtin_offsetof(t,m)
void* memcpy(void*d,const void*s,size_t n){volatile unsigned char*a=d;const volatile unsigned char*b=s;while(n--)*a++=*b++;return d;}
typedef struct {unsigned char legacy[13];bool arrow_double_tap_boost,arrow_double_tap_boost_v1;} user_settings_ext;
static int migrate(unsigned char done,unsigned char value,size_t written,size_t bytes_read){
 user_settings_ext e={0};user_settings_ext*ext=&e;size_t ext_at=0;int fixed=0;
 memcpy(&e.arrow_double_tap_boost,&value,1);memcpy(&e.arrow_double_tap_boost_v1,&done,1);
'''+migration+r'''
 unsigned char actual=2;memcpy(&actual,&e.arrow_double_tap_boost,1);return actual+(fixed?10:0);
}
'''
code+=r'''
#define CHECK(c) do{if(!(c))return __LINE__;}while(0)
static bool press(tenv*e,uint64_t finger,float x,float y){
 SDL_Event down={SDL_EVENT_FINGER_DOWN};
 return original?original_touch(e,&down,finger,x,y):wyrm_touch_down(e,finger,x,y);
}
static int returning(tenv*e,bool near,bool button,bool portrait){
 original=near;mode=2;clock_ms+=1000;
 e->wnd->size[0]=portrait?500:1000;e->wnd->size[1]=portrait?1000:500;
 mobile_controls_state*s=&e->usr->mobile_controls;
 e->usr->usrs.mobile_controls.boost_mode=button?1:0;reset_touches(s);
 float ax=e->wnd->size[0]*.7f;
 float bx=button?(near?100:e->usr->usrs.mobile_controls.boost_x*e->wnd->size[0]):e->wnd->size[0]*.3f;
 float by=button?(near?400:e->usr->usrs.mobile_controls.boost_y*e->wnd->size[1]):100;
 CHECK(press(e,201,ax,200));CHECK(press(e,202,bx,by));CHECK(mobile_controls_boost_down(e));
 CHECK(s->joystick_finger==201);
 track_boost_motion(e,202,bx+10,by);CHECK(s->joystick_finger==201);
 finish_touch(e,2,201);CHECK(!s->joystick_down);CHECK(mobile_controls_boost_down(e));
 track_boost_motion(e,202,bx+40,by);CHECK(!s->joystick_down);
 track_boost_motion(e,202,bx+84,by);CHECK(!s->joystick_down); /* exactly74 after release */
 e->usr->gdata.data.vfrb=1;decay_boost_motion(e);CHECK(fabsf(boost_motion_total-72.7f)<.001f);
 e->usr->gdata.data.vfrb=0;
 track_boost_motion(e,202,bx+87,by);CHECK(s->joystick_down&&s->joystick_finger==202);CHECK(mobile_controls_boost_down(e));
 int before=arrow_moves;track_boost_motion(e,202,bx+90,by);CHECK(arrow_moves==before+1);
 CHECK(press(e,203,ax,200));CHECK(s->joystick_finger==203);CHECK(s->boost_finger==202&&mobile_controls_boost_down(e));
 before=arrow_moves;track_boost_motion(e,202,bx+200,by);CHECK(arrow_moves==before&&s->joystick_finger==203);
 press(e,204,ax,250);CHECK(s->joystick_finger==203&&s->boost_finger==202);
 finish_touch(e,3,202);CHECK(!mobile_controls_boost_down(e)&&s->joystick_down&&s->joystick_finger==203);
 finish_touch(e,2,203);CHECK(!s->joystick_down);
 /* Return before promotion also reclaims steering, without a new boost owner. */
 reset_touches(s);press(e,211,ax,200);press(e,212,bx,by);finish_touch(e,2,211);
 CHECK(press(e,213,ax,210));CHECK(s->joystick_finger==213&&s->boost_finger==212&&mobile_controls_boost_down(e));
 reset_touches(s);CHECK(!mobile_controls_boost_down(e));return 0;
}
__attribute__((export_name("test"))) int test(void){
 user u={0};window w={{1000,500}};tenv e={&w,&u};
 CHECK(migrate(0,0,100,100)==11);CHECK(migrate(1,0,100,100)==0);
 CHECK(migrate(1,1,100,100)==1);CHECK(migrate(1,9,100,100)==11);
 CHECK(migrate(1,0,0,0)==11);
 mobile_controls_state*s=&u.mobile_controls;mobile_control_settings*c=&u.usrs.mobile_controls;
 c->joystick_x=.8f;c->joystick_y=.7f;c->boost_x=.1f;c->boost_y=.8f;c->joystick_size=c->boost_size=1;
 mode=2;c->boost_mode=1;u.usrs.ext.arrow_double_tap_boost=true;clock_ms=1000;sync_touch_policy(&e);
 CHECK(wyrm_touch_down(&e,11,700,200));CHECK(!mobile_controls_boost_down(&e));
 CHECK(!wyrm_touch_down(&e,12,600,100));CHECK(!mobile_controls_boost_down(&e));
 finish_touch(&e,2,11);clock_ms=1200;wyrm_touch_down(&e,13,700,200);CHECK(!mobile_controls_boost_down(&e));
 CHECK(!wyrm_touch_down(&e,14,190,400));CHECK(!mobile_controls_boost_down(&e));
 CHECK(wyrm_touch_down(&e,15,100,400));CHECK(mobile_controls_boost_down(&e));
 finish_touch(&e,3,15);CHECK(!mobile_controls_boost_down(&e));
 c->boost_mode=0;sync_touch_policy(&e);CHECK(!s->joystick_down);clock_ms=2000;
 wyrm_touch_down(&e,21,700,200);wyrm_touch_down(&e,21,700,200);CHECK(!mobile_controls_boost_down(&e));
 wyrm_touch_down(&e,22,600,100);CHECK(mobile_controls_boost_down(&e));
 finish_touch(&e,2,21);CHECK(!s->joystick_down);CHECK(mobile_controls_boost_down(&e));
 finish_touch(&e,2,22);CHECK(!s->joystick_down&&!mobile_controls_boost_down(&e));
 reset_touches(s);clock_ms=3000;wyrm_touch_down(&e,31,700,200);finish_touch(&e,2,31);
 clock_ms=3200;wyrm_touch_down(&e,32,701,201);CHECK(mobile_controls_boost_down(&e));
 finish_touch(&e,2,32);CHECK(!mobile_controls_boost_down(&e));
 reset_touches(s);clock_ms=4000;wyrm_touch_down(&e,41,700,200);finish_touch(&e,3,41);
 clock_ms=4200;wyrm_touch_down(&e,42,700,200);CHECK(!mobile_controls_boost_down(&e));
 u.usrs.ext.arrow_double_tap_boost=false;sync_touch_policy(&e);clock_ms=5000;
 wyrm_touch_down(&e,51,700,200);finish_touch(&e,2,51);clock_ms=5200;wyrm_touch_down(&e,52,700,200);CHECK(!mobile_controls_boost_down(&e));
 mode=1;c->boost_mode=1;sync_touch_policy(&e);CHECK(wyrm_touch_down(&e,61,990,10));CHECK(s->joystick_down);CHECK(!mobile_controls_boost_down(&e));
 CHECK(!wyrm_touch_down(&e,62,250,20));CHECK(!mobile_controls_boost_down(&e));
 wyrm_touch_down(&e,63,100,400);CHECK(mobile_controls_boost_down(&e));finish_touch(&e,2,63);CHECK(!mobile_controls_boost_down(&e));
 c->boost_mode=0;sync_touch_policy(&e);wyrm_touch_down(&e,71,990,10);
 CHECK(!wyrm_touch_down(&e,72,900,20));CHECK(!mobile_controls_boost_down(&e));
 wyrm_touch_down(&e,73,250,20);CHECK(mobile_controls_boost_down(&e));finish_touch(&e,3,73);CHECK(!mobile_controls_boost_down(&e));
 reset_touches(s);c->joystick_x=.2f;wyrm_touch_down(&e,81,10,10);CHECK(s->joystick_down);wyrm_touch_down(&e,82,990,10);CHECK(mobile_controls_boost_down(&e));
 mode=0;c->handedness=0;sync_touch_policy(&e);wyrm_touch_down(&e,91,10,20);CHECK(s->joystick_down);wyrm_touch_down(&e,92,990,20);CHECK(mobile_controls_boost_down(&e));
 mode=3;c->boost_mode=0;sync_touch_policy(&e);classic_fingers[0].down=true;classic_fingers[1].down=true;classic_fingers[1].ignored=true;CHECK(mobile_controls_boost_down(&e));
 c->boost_mode=1;sync_touch_policy(&e);classic_fingers[0].down=true;classic_fingers[1].down=true;CHECK(!mobile_controls_boost_down(&e));
 for(int near=0;near<2;++near)for(int button=0;button<2;++button)for(int portrait=0;portrait<2;++portrait){
  if(near&&!button&&!portrait)continue; /* original landscape uses its boost button */
  int result=returning(&e,near,button,portrait);if(result)return result;
 }
 original=false;w.size[0]=1000;w.size[1]=500;
 for(int stick=0;stick<2;++stick)for(int left=0;left<2;++left)for(int button=0;button<2;++button){
  mode=stick;c->handedness=left?0:1;c->joystick_x=left?.2f:.8f;c->boost_x=left?.9f:.1f;c->boost_mode=button?1:0;reset_touches(s);
  float ax=left?20:980,bx=left?900:100;
  CHECK(press(&e,301,ax,20));CHECK(press(&e,302,bx,400));CHECK(mobile_controls_boost_down(&e));
  finish_touch(&e,2,301);CHECK(!s->joystick_down&&mobile_controls_boost_down(&e));
  track_boost_motion(&e,302,bx+100,400);CHECK(!s->joystick_down); /* no joystick stealing */
  CHECK(press(&e,303,ax,20));CHECK(s->joystick_finger==303&&s->boost_finger==302);
  finish_touch(&e,2,302);CHECK(!mobile_controls_boost_down(&e)&&s->joystick_finger==303);
 }
 original=true;mode=1;
 for(int left=0;left<2;++left){
  c->joystick_x=left?.2f:.8f;c->boost_x=left?.9f:.1f;c->boost_y=.8f;reset_touches(s);
  float ax=left?20:980,bx=left?900:100;
  CHECK(press(&e,401,ax,20));CHECK(press(&e,402,bx,400));CHECK(mobile_controls_boost_down(&e));
  finish_touch(&e,2,401);CHECK(!s->joystick_down&&mobile_controls_boost_down(&e));
  track_boost_motion(&e,402,bx+100,400);CHECK(!s->joystick_down);
  CHECK(press(&e,403,ax,20));CHECK(s->joystick_finger==403&&s->boost_finger==402);
  finish_touch(&e,2,402);CHECK(!mobile_controls_boost_down(&e)&&s->joystick_down);
 }
 return 0;
}
'''
clang=Path(os.environ.get('LOCALAPPDATA',''))/'Android/Sdk/ndk/28.2.13676358/toolchains/llvm/prebuilt/windows-x86_64/bin/clang.exe'
with tempfile.TemporaryDirectory() as temp:
 p=Path(temp)
 if clang.exists():
  (p/'test.c').write_text(code,encoding='utf-8')
  subprocess.run([str(clang),'--target=wasm32','-nostdlib','-Wl,--no-entry','-Wl,--export-memory','-O2',str(p/'test.c'),'-o',str(p/'test.wasm')],check=True)
  subprocess.run(['node','-e',"WebAssembly.instantiate(require('fs').readFileSync(process.argv[1]),{}).then(({instance})=>{let r=instance.exports.test();if(r)throw Error('Boost C assertion line '+r);console.log('Production boost/touch policy passed')})",str(p/'test.wasm')],check=True)
 else:
  native=code.replace('__attribute__((export_name("test")))','')+'\nint main(void){return test();}\n'
  (p/'test.c').write_text(native,encoding='utf-8')
  subprocess.run([shutil.which('clang') or 'cc','-O2',str(p/'test.c'),'-o',str(p/'test')],check=True);subprocess.run([str(p/'test')],check=True)
assert '160.0f * original_unit(env)' in source
assert 'draw_paper_disc(dl,cx,cy,base,a,false)' in source
for file in ['SourcesShell/WyrmSettingsPages.swift','SourcesShell/WyrmAccountSync.swift']:
 assert 'arrow.double_tap_boost' in (ROOT/file).read_text(encoding='utf-8')
assert 'arrowDoubleTapBoost' in (ROOT/'SourcesShell/WyrmAccountSync.swift').read_text(encoding='utf-8')
print('Original hit radius, stable native skin, Arrow toggle and shared account key retained')
