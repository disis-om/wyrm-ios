"""Held boost survives steering release; returning steering reclaims its role."""
from pathlib import Path
import sys

PAIRS={
'app/src/mobile/mobile_controls.c':[
('static bool boost_secondary;','static bool boost_secondary;\nstatic bool boost_steering_promoted;\nstatic float boost_motion_total, boost_motion_last[2];'),
('  boost_secondary = false;\n  memset(classic_fingers,', '  boost_secondary = false;\n  boost_steering_promoted = false; boost_motion_total = 0;\n  memset(classic_fingers,'),
('    if (boost_secondary) { state->boost_down = false; boost_secondary = false; }','    boost_steering_promoted = false; boost_motion_total = 0;'),
('    state->boost_down = false; boost_secondary = false;','    state->boost_down = false; boost_secondary = false;\n    boost_steering_promoted = false; boost_motion_total = 0;'),
('  boost_secondary = secondary;','  boost_secondary = secondary;\n  boost_steering_promoted = false; boost_motion_total = 0;\n  boost_motion_last[0] = x; boost_motion_last[1] = y;'),
('static bool original_touch(tenv* env, const SDL_Event* event, uint64_t finger,', '''/* A booster may steer alone, but a fresh steering contact takes that role back. */
static void reclaim_arrow_steering(mobile_controls_state* state) {
  if (boost_steering_promoted && state->boost_down && state->joystick_down &&
      state->joystick_finger == state->boost_finger) {
    state->joystick_down = false;
    boost_steering_promoted = false; boost_motion_total = 0;
  }
}

static bool original_touch(tenv* env, const SDL_Event* event, uint64_t finger,'''),
('    if (arrow) {\n      if (!state->joystick_down)', '    if (arrow) {\n      reclaim_arrow_steering(state);\n      if (!state->joystick_down)'),
('''    bool handoff = boost_secondary && state->boost_down && state->joystick_down &&
        state->joystick_finger==finger && state->boost_finger!=finger;
    uint64_t next=state->boost_finger;
    float nx=state->boost_origin[0], ny=state->boost_origin[1];
''',''),
('''    if (handoff) {
      state->joystick_down=true; state->joystick_finger=next;
      state->joystick_origin[0]=nx; state->joystick_origin[1]=ny;
      state->arrow_drag_distance=0; arrow_seed(env,nx,ny);
    }
''',''),
('''  if (env->wnd->size[1]>env->wnd->size[0] && mode==MOBILE_JOYSTICK_DYNAMIC)
    own_half=!state->joystick_down;
''',''),
('  if (mode==MOBILE_STEERING_ARROW) {\n    if (state->joystick_down', '  if (mode==MOBILE_STEERING_ARROW) {\n    reclaim_arrow_steering(state);\n    if (state->joystick_down'),
('bool mobile_controls_process_event(tenv* env, const void* raw_event) {', '''/* Main.as trackTouch: an otherwise ignored booster can steer after 74 units
   of accumulated movement when no steering contact remains. Boost ownership
   stays independent, including while the returning contact resumes steering. */
static bool track_boost_motion(tenv* env, uint64_t finger, float x, float y) {
  mobile_controls_state* state = &env->usr->mobile_controls;
  if (!state->boost_down || state->boost_finger != finger) return false;
  float travel = fabsf(x-boost_motion_last[0]) + fabsf(y-boost_motion_last[1]);
  boost_motion_last[0]=x; boost_motion_last[1]=y;
  state->boost_origin[0]=x; state->boost_origin[1]=y;
  if (mobile_controls_steering_mode(env) == MOBILE_STEERING_ARROW) {
    if (!state->joystick_down) {
      boost_motion_total += travel;
      if (boost_motion_total > 74.0f * original_unit(env)) {
        state->joystick_down=true; state->joystick_finger=finger;
        state->joystick_origin[0]=x; state->joystick_origin[1]=y;
        state->arrow_drag_distance=0; arrow_seed(env,x,y);
        boost_steering_promoted=true;
      }
    } else if (boost_steering_promoted && state->joystick_finger==finger) {
      update_arrow(env,x,y);
    }
  }
  return true;
}

static void decay_boost_motion(tenv* env) {
  mobile_controls_state* state = &env->usr->mobile_controls;
  if (mobile_controls_steering_mode(env) == MOBILE_STEERING_ARROW &&
      state->boost_down && !state->joystick_down) {
    int steps = env->usr->gdata.data.vfrb;
    if (steps < 0) steps=0; else if (steps > 120) steps=120;
    boost_motion_total -= steps * 1.3f * original_unit(env);
    if (boost_motion_total < 0) boost_motion_total=0;
  }
}

bool mobile_controls_process_event(tenv* env, const void* raw_event) {'''),
('''  if (event->type==SDL_EVENT_FINGER_MOTION && boost_secondary && state->boost_down && state->boost_finger==finger) {
    state->boost_origin[0]=x; state->boost_origin[1]=y; return true;
  }''','''  if (event->type==SDL_EVENT_FINGER_MOTION && track_boost_motion(env,finger,x,y)) return true;'''),
('  return state->boost_down && (!boost_secondary || state->joystick_down);','  return state->boost_down;'),
('    float vfr = gdata->data.vfr;', '    decay_boost_motion(env);\n    float vfr = gdata->data.vfr;'),
]}

def apply(root,dry=False):
 pending=[]
 for file,changes in PAIRS.items():
  p=Path(root)/file;s=p.read_text(encoding='utf-8')
  # Reverse only non-empty replacement anchors when this patch is already applied.
  applied='static bool track_boost_motion(' in s
  if applied:
   if not dry:raise AssertionError('Returning-finger patch already applied')
   # Reconstruct the original using stable neighbouring anchors for removals.
   s=s.replace('  float scale=control_scale(env);\n  if (!state->zoom_down', '  if (env->wnd->size[1]>env->wnd->size[0] && mode==MOBILE_JOYSTICK_DYNAMIC)\n    own_half=!state->joystick_down;\n  float scale=control_scale(env);\n  if (!state->zoom_down',1)
   s=s.replace('  mobile_controls_state* state=&env->usr->mobile_controls;\n    if (arrow_last_down_finger', '  mobile_controls_state* state=&env->usr->mobile_controls;\n'+changes[7][0]+'    if (arrow_last_down_finger',1)
   s=s.replace('    release_owned_touch(state, finger);\n}\n\nstatic bool wyrm_touch_down', '    release_owned_touch(state, finger);\n'+changes[8][0]+'}\n\nstatic bool wyrm_touch_down',1)
   for before,after in reversed(changes):
    if after:
     assert s.count(after)==1,(file,'reverse',after[:70],s.count(after))
     s=s.replace(after,before,1)
  for before,after in changes:
   assert s.count(before)==1,(file,before[:70],s.count(before))
   s=s.replace(before,after,1)
  pending.append((p,s))
 if not dry:
  for p,s in pending:p.write_text(s,encoding='utf-8')
 print('Returning finger: '+str(sum(map(len,PAIRS.values())))+' single anchors; dry='+str(dry))
if __name__=='__main__':apply(sys.argv[1],'--dry' in sys.argv)
