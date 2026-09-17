"""Verify the Android snapshot and prepare a disposable Apple compile tree.

Gameplay and protocol sources are never edited in place. Platform selection
changes below are deliberately explicit so the source delta is reviewable.
"""
import hashlib
import json
from pathlib import Path
import shutil
import re

ROOT = Path(__file__).resolve().parent.parent
SOURCE = ROOT / "SharedEngine"
OUTPUT = ROOT / "build-original-source"

sdl_headers = list((ROOT / "Vendor" / "SDL3.xcframework").rglob("SDL.h"))
if sdl_headers:
    shutil.copytree(sdl_headers[0].parent, ROOT / "Vendor" / "SDLInclude" / "SDL3", dirs_exist_ok=True)

manifest = json.loads((SOURCE / "SHA256.json").read_text())
for relative, expected in manifest.items():
    actual = hashlib.sha256((SOURCE / relative).read_bytes()).hexdigest()
    if actual != expected:
        raise SystemExit(f"Original source changed: {relative}")

for relative in manifest:
    destination = OUTPUT / relative
    destination.parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(SOURCE / relative, destination)

# VLITHER_ANDROID currently selects both SDL and JNI. Select SDL on Apple
# in non-service files only; Android service files retain their existing
# non-Android fallback until a real Apple service adapter replaces each one.
changed = []

def function_span(text, name):
    # Ignore braces in comments/strings while locating a complete C function.
    masked = re.sub(r'//[^\n]*|/\*[\s\S]*?\*/|"(?:\\.|[^"\\])*"|\x27(?:\\.|[^\x27\\])*\x27',
                    lambda m: ' ' * len(m.group()), text)
    match = re.search(r'\b' + re.escape(name) + r'\s*\([^;{}]*\)\s*\{', masked)
    if not match:
        raise RuntimeError(f"Missing original function: {name}")
    start = masked.index('{', match.start())
    depth = 1
    end = start + 1
    while depth:
        depth += (masked[end] == '{') - (masked[end] == '}')
        end += 1
    return start, end

def replace_body(text, name, body):
    start, end = function_span(text, name)
    return text[:start] + '{\n' + body + '\n}' + text[end:]

for path in sorted(OUTPUT.rglob("*")):
    if path.suffix not in (".c", ".cpp", ".h"):
        continue
    relative = path.relative_to(OUTPUT).as_posix()
    text = path.read_text(encoding="utf-8-sig")
    original = text
    if not relative.startswith("app/src/platform/"):
        text = text.replace("VLITHER_ANDROID", "WYRM_MOBILE")
    if relative == "app/src/game/redraw.c":
        text = text.replace("__ANDROID__", "WYRM_MOBILE")
    if relative == "app/src/game/arena_theme.c":
        text = text.replace("#include <jni.h>", "#ifdef __ANDROID__\n#include <jni.h>\n#endif")
        text = text.replace("JNIEXPORT void JNICALL", "#ifdef __ANDROID__\nJNIEXPORT void JNICALL", 1)
        text += "\n#endif\n"
    if relative == "app/src/main.c":
        text = text.replace('TDEF_ENTRY();', '')
        text = '#include "WyrmOriginalAdapter.h"\n' + text
        text = text.replace('  ui_theme_transition_end(env);',
                            '  ui_theme_transition_end(env);\n  WyrmIOSDrawShell(env);')
    if relative == "app/src/imgui_setup.c":
        # Android exposes one pixel coordinate space to both Vulkan and ImGui.
        # SDL on Retina iOS instead reports logical points to ImGui while the
        # engine texture, HUD geometry and mobile controls remain in drawable
        # pixels. Mixing the two made ui_viewport draw a 2868x1320 image into a
        # 956x440 canvas: only its top-left third was visible, so the minimap
        # and nearby snakes looked three times too large. Keep the original
        # Android pixel contract for the rotated engine surface. UIKit still
        # scales that surface to the physical portrait display.
        marker = '''#ifdef WYRM_MOBILE
  igImplSDL3_NewFrame();
#else'''
        assert text.count(marker) == 1
        text = text.replace(marker, '''#ifdef WYRM_MOBILE
  igImplSDL3_NewFrame();
#ifdef __APPLE__
  ImGuiIO* apple_io = igGetIO_Nil();
  apple_io->DisplaySize = (ImVec2){(float)android_env->ctx->size[0],
                                   (float)android_env->ctx->size[1]};
  apple_io->DisplayFramebufferScale = (ImVec2){1.0f, 1.0f};
#endif
#else''')
    if relative == "app/src/platform/android_startup.c":
        text = text.replace('VLITHER_ANDROID', 'WYRM_MOBILE')
    if relative == "app/src/platform/android_home.c":
        # Preserve the original mailboxes, join admission and death state machine.
        # Only JNI publication and JNI exports are replaced by Apple-facing C calls.
        text = '#include "WyrmOriginalAdapter.h"\n' + text
        text = text[:text.index('JNIEXPORT void JNICALL')]
        text = text.replace('#ifdef VLITHER_ANDROID', '').replace('#include <jni.h>', '')
        for name in ('get_activity', 'clear_exception'):
            start, end = function_span(text, name)
            start = text.rfind('\n', 0, text.rfind('static ', 0, start)) + 1
            text = text[:start] + text[end:]
        for name, body in {
            'record_finished_run': '(void)env; /* Local score is retained by the original engine. */',
            'android_home_set_screen': '(void)screen;',
            'android_home_publish_state': '(void)env_ptr;',
            'android_home_arena_refused': 'SDL_Log("Wyrm arena refused: %s (%d seconds)", endpoint, seconds);',
        }.items():
            text = replace_body(text, name, body)
        for name in ('raise_death_card', 'dismiss_death'):
            start, end = function_span(text, name)
            body = text[start + 1:end - 1]
            body = body[:body.index('  JNIEnv*')]
            text = replace_body(text, name, body)
        text += (ROOT / 'SourcesOriginal' / 'HomeMailbox.inc').read_text()
    if relative == "thermite/src/framework/twindow.c":
        # iOS stays system-portrait for the entire app. The temporary Apple
        # Home starts portrait; the adapter rotates and swaps only this SDL
        # surface for the untouched original landscape lobby/arena renderer.
        window_size = 'env->config.title, 1280, 720,'
        assert text.count(window_size) == 1
        text = text.replace(window_size, 'env->config.title, 720, 1280,')
    if relative == "app/src/cimgui/imgui/imgui_impl_vulkan.cpp":
        # Same indexed geometry, but move base vertex into the buffer binding.
        # SimMetal does not implement non-zero baseVertex draws.
        draw = 'vkCmdDrawIndexed(command_buffer, pcmd->ElemCount, 1, pcmd->IdxOffset + global_idx_offset, pcmd->VtxOffset + global_vtx_offset, 0);'
        assert text.count(draw) == 1
        text = '#include <TargetConditionals.h>\n' + text
        text = text.replace(draw, '''
#if TARGET_OS_SIMULATOR
                VkDeviceSize apple_vertex_offset = (VkDeviceSize)(pcmd->VtxOffset + global_vtx_offset) * sizeof(ImDrawVert);
                vkCmdBindVertexBuffers(command_buffer, 0, 1, &rb->VertexBuffer, &apple_vertex_offset);
                vkCmdDrawIndexed(command_buffer, pcmd->ElemCount, 1, pcmd->IdxOffset + global_idx_offset, 0, 0);
#else
                ''' + draw + '''
#endif''')
    if relative == "thermite/src/graphics/tcontext.c":
        text = '#include "WyrmOriginalAdapter.h"\n' + text
        text = text.replace('vkCreateInstance(', 'WyrmIOSCreateInstance(')
        text = text.replace('vkCreateDevice(', 'WyrmIOSCreateDevice(')
    if text != original:
        path.write_text(text, encoding="utf-8")
        changed.append(relative)
print(f"Verified {len(manifest)} original files; platform selection adjusted in {len(changed)} files")
(OUTPUT / "platform-selection.json").write_text(json.dumps(changed, indent=2))
