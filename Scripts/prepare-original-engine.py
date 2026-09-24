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
        text = text.replace('  android_skin_poll(env);',
                            '  android_skin_poll(env);\n  WyrmIOSApplySkinSelection(env);')
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
            'android_home_arena_refused': '''WyrmIOSPublishArenaRefusal(endpoint, seconds);
  SDL_Log("Wyrm arena refused: %s (%d seconds)", endpoint, seconds);''',
        }.items():
            text = replace_body(text, name, body)
        for name in ('raise_death_card', 'dismiss_death'):
            start, end = function_span(text, name)
            body = text[start + 1:end - 1]
            body = body[:body.index('  JNIEnv*')]
            text = replace_body(text, name, body)
        text += (ROOT / 'SourcesOriginal' / 'HomeMailbox.inc').read_text()
    if relative == "app/src/game/game_data.c":
        # One explicit Play request may wait for the old socket to finish,
        # but must never schedule a second dial after its first dial fails.
        pending = 'gdata->rejoin_at_ms = server_connect(env) ? 0 : now + 50;'
        assert text.count(pending) == 1
        text = text.replace(pending, '''gdata->rejoin_at_ms = 0;
  if (!server_connect(env)) game_fail_connection(gdata, "previous socket still closing");''')
    if relative == "app/src/game/loop.c":
        pending = 'if (!server_connect(env)) gdata->rejoin_at_ms = SDL_GetTicks() + 50;'
        assert text.count(pending) == 1
        text = text.replace(pending, 'if (!server_connect(env)) game_fail_connection(gdata, "previous socket still closing");')
        timeout_clock = 'SDL_GetTicks() - gdata->attempt_started_ms > ARENA_RETRY_MS'
        assert text.count(timeout_clock) == 1
        text = text.replace(timeout_clock, 'SDL_GetTicks() - gdata->attempt_started_ms > 5000')
        connect_gate = 'if (!gdata->arena_ready && gdata->connection &&'
        assert text.count(connect_gate) == 1
        text = text.replace(connect_gate, 'if (gdata->connection &&')
        timeout = '''          arena_taint_mark(usrs->ipv4);
          android_home_arena_refused(
              usrs->ipv4, (int)(arena_taint_remaining(usrs->ipv4) / 1000));
          game_fail_connection(gdata, "configuration timeout");'''
        assert text.count(timeout) == 1
        text = text.replace(timeout, '          game_fail_connection(gdata, "configuration timeout");')
        failed = '''          /* Slither taints a refused arena and chooses another one. Retrying
             the same endpoint forever both hid the actual failure and caused
             the fleet to throttle the phone. Compose owns the live directory,
             so hand the refusal back to it and let it pick the next reachable
             endpoint after the lobby has settled. */
          arena_taint_mark(usrs->ipv4);
          android_home_arena_refused(
              usrs->ipv4, (int)(arena_taint_remaining(usrs->ipv4) / 1000));
          game_data_reset(env);
          gdata->conn = DISCONNECTED;
          gdata->curr_screen = LOBBY;'''
        assert text.count(failed) == 1
        text = text.replace(failed, '''          /* Vlither ends this connection attempt here. On iOS the native
             landscape lobby is the equivalent of its title screen. */
          android_home_arena_refused(usrs->ipv4, 0);
          game_data_reset(env);
          gdata->conn = DISCONNECTED;
          gdata->curr_screen = LOBBY;''')
    if relative == "app/src/network/callback.c":
        # Preserve real death packets. A silent short life is a terminal
        # refusal of this Play attempt, never an automatic retry or failover.
        # Preserve every original gameplay packet. Add only socket-stage
        # diagnostics, so a silent pre-upgrade close cannot be mistaken for a
        # rejected challenge or a post-spawn protocol failure.
        opened = '  } else if (ev == MG_EV_WS_OPEN) {'
        assert text.count(opened) == 1
        text = text.replace(opened, '''  } else if (ev == MG_EV_CONNECT) {
    SDL_Log("Wyrm arena: TCP connected to '%s'", usr->usrs.ipv4);
  } else if (ev == MG_EV_WS_OPEN) {
    SDL_Log("Wyrm arena: WebSocket upgraded for '%s'", usr->usrs.ipv4);''')
        error = '  } else if (ev == MG_EV_ERROR) {'
        assert text.count(error) == 1
        text = text.replace(error, '''  } else if (ev == MG_EV_WS_CTL) {
    struct mg_ws_message* ctl = (struct mg_ws_message*)ev_data;
    if (ctl && (ctl->flags & 15) == WEBSOCKET_OP_CLOSE) {
      unsigned code = ctl->data.len >= 2
          ? ((unsigned)(uint8_t)ctl->data.buf[0] << 8) |
            (uint8_t)ctl->data.buf[1]
          : 0;
      SDL_Log("Wyrm arena: WebSocket close frame from '%s' code=%u",
              usr->usrs.ipv4, code);
    }
  } else if (ev == MG_EV_ERROR) {''')
        joined = '    arena_send(c, ba, m);\n    free(ba);'
        assert text.count(joined) == 1
        text = text.replace(joined, '''    SDL_Log("Wyrm arena: join fields accessory=%u custom_skin=%d nickname_bytes=%d packet_bytes=%d",
            (unsigned)usrs->accessory, usrs->custom_skin ? 1 : 0,
            nick_len, m);
    arena_send(c, ba, m);
    free(ba);''')
        closing = '    gdata->last_life = gdata->join_spawned ? glfwGetTime() - gdata->life_started_sec : 0;'
        assert text.count(closing) == 1
        text = text.replace(closing, '''    const char* phase = !c->is_websocket ? "before WebSocket upgrade" :
        !gdata->persona_tested ? "before challenge" :
        !gdata->arena_ready ? "after challenge, before configuration" :
        !gdata->join_spawned ? "after configuration, before spawn" :
        "after spawn";
    SDL_Log("Wyrm arena: socket closed in phase '%s' after %llums",
            phase, (unsigned long long)(SDL_GetTicks() - gdata->attempt_started_ms));
''' + closing)
        close_block = '''    if (gdata->arena_ready && gdata->curr_screen == PLAYING &&
        !gdata->leaving && !gdata->restart_req) {
      android_home_notify_death(env);
      game_clear_world(gdata);
      gdata->arena_ready = false;
    }
'''
        assert text.count(close_block) == 1
        text = text.replace(close_block, '''    bool refused_short_life =
        gdata->arena_ready && gdata->join_spawned &&
        gdata->last_life > 0 && gdata->last_life < SHORT_LIFE &&
        !gdata->closed_by_us && !gdata->leaving && !gdata->restart_req &&
        !android_home_death_pending();
    if (refused_short_life) {
      android_home_arena_refused(usr->usrs.ipv4, 0);
      /* A genuine 'v' packet already armed the death watch. A silent short
         life returns to the native lobby without a second dial. */
      gdata->join_spawned = false;
    }
    if (gdata->arena_ready && gdata->curr_screen == PLAYING &&
        !gdata->leaving && !gdata->restart_req) {
      if (!refused_short_life && gdata->join_spawned)
        android_home_notify_death(env);
      game_clear_world(gdata);
      gdata->arena_ready = false;
    }
''')
    if relative == "app/src/platform/android_settings.c":
        # The settings table, validation, persistence and once-per-frame
        # mailbox are engine code, not Android UI code. Compile that exact
        # implementation on Apple and replace only its JNI publication edge
        # with a narrow C ABI consumed by Swift.
        text = text.replace('#ifdef VLITHER_ANDROID',
                            '#if defined(VLITHER_ANDROID) || defined(WYRM_IOS)', 1)
        text = text.replace('#include <jni.h>',
                            '#ifdef __ANDROID__\n#include <jni.h>\n#endif', 1)
        jni_start = text.index('JNIEXPORT jstring JNICALL')
        outer_else = text.rfind('\n#else\n')
        assert jni_start > 0 and outer_else > jni_start
        apple = (ROOT / 'SourcesOriginal' / 'AppleSettingsMailbox.inc').read_text()
        text = (text[:jni_start] + '#ifdef __ANDROID__\n' +
                text[jni_start:outer_else] + '\n#else\n' + apple +
                '\n#endif\n' + text[outer_else:])
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
