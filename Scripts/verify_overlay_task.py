from pathlib import Path
import subprocess, os, json, re
R=Path('D:/wyrm'); os.chdir(R)
CL=Path('C:/Users/Om Rajput/AppData/Local/Android/Sdk/ndk/28.2.13676358/toolchains/llvm/prebuilt/windows-x86_64/bin/clang.exe')
files=['game/arena_theme.c','rendering/renderer.c','game/ui_overlay.c','game/redraw.c','game/user_settings.c','platform/android_settings.c','platform/android_team.c','mobile/mobile_controls.c','mobile/mobile_hotkeys.c','game/loop.c']
base=['--target=aarch64-linux-android26','-std=c11','-fsyntax-only','-Wall','-Wextra','-Wno-unused-parameter','-DSETTINGS_VERSION="2.8"','-DCIMGUI_NO_EXPORT','-DCGLM_FORCE_DEPTH_ZERO_TO_ONE','-DMG_ENABLE_IPV6=1']
for label,tree,defs in [('Android','Wyrm Android',['-DWYRM_SDL_JNI=1']),('iOS','Wyrm iOS/build-original-source',['-DWYRM_MOBILE=1','-DWYRM_IOS=1','-DAPP_VERSION="2.4.1"']),('Desktop','Wyrm Android',['-DWYRM_SDL_JNI=1','-DWYRM_DESKTOP=1'])]:
    inc=['-I'+tree+'/app/src','-IWyrm Android/android/app/.cxx-version','-I'+tree+'/thermite/include','-I'+tree+'/thermite/src','-IWyrm Android/android-sdl/include','-IWyrm iOS/SourcesOriginal','-IWyrm Android/glfw/include','-DGLFW_INCLUDE_NONE']
    for file in files:
        r=subprocess.run([str(CL),*base,*defs,*inc,tree+'/app/src/'+file],capture_output=True,text=True,encoding='utf-8')
        print(label,file,'exit',r.returncode)
        print('warnings',r.stderr.count('warning:'),'errors',r.stderr.count(' error:'))
        if r.returncode: print(r.stderr)
        if r.returncode: raise SystemExit(r.returncode)

a=(R/'Wyrm Android/app/src/game/redraw.c').read_text(encoding='utf-8')
b=(R/'Wyrm iOS/build-original-source/app/src/game/redraw.c').read_text(encoding='utf-8')
for t in [a,b]:
    assert t.count('float d = gdata->fsz[fo->cv2] * food_scale * fo->rad * mode->food_scale;')==2
    assert t.count('original_food(usr->r,fx+d*.5f,fy+d*.5f,d,c,fo->fr,')==2
    assert 'float food_scale = gdata->data.gsc;' in t
    assert 'blend' not in t[t.index('  if (mode->uniform_food_color)'):t.index('  /* Battledome letters and dome:')]
start='  if (mode->uniform_food_color)'; end='  /* Battledome letters and dome:'
assert a[a.index(start):a.index(end)]==b[b.index(start):b.index(end)]
print('Food blocks: identical Android/iOS, common diameter, no screen-fixed scaling')
