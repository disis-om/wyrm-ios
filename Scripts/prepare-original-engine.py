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

# The slither.io Android (AIR) Build-a-Slither beads. The atlas below is the
# original one plus three cells written by Scripts/generate-air-skin-assets.py
# (exact ports of AIR's nsk 0/1 bead bitmaps and its `ksmc_t` shadow, checked
# against the baked AIR sheets). Both hashes are pinned so neither can drift.
ORIGINAL_ATLAS_SHA256 = "73805db544b97b51c3ce7d898dbc48d5ea2bc173dcd402e072f0c63642342fed"
AIR_ATLAS = ROOT / "Resources" / "AirSkin" / "tex_atlas_8k.png"
AIR_ATLAS_SHA256 = "cf9e6251272704d6161cfeea875b6a5ba0d276a161c332ae0d6d5029487be7a9"
atlas_target = OUTPUT / "app/res/textures/tex_atlas_8k.png"
if hashlib.sha256(atlas_target.read_bytes()).hexdigest() != ORIGINAL_ATLAS_SHA256:
    raise SystemExit("Original atlas changed; regenerate Resources/AirSkin")
if hashlib.sha256(AIR_ATLAS.read_bytes()).hexdigest() != AIR_ATLAS_SHA256:
    raise SystemExit("Resources/AirSkin/tex_atlas_8k.png does not match its pinned hash")
shutil.copyfile(AIR_ATLAS, atlas_target)

AIR_HELPERS = r'''/* Wyrm iOS — the slither.io Android client's Build-a-Slither beads.
 *
 * A bead built with the colour wheel keeps its exact picked RGB in the low
 * 24 bits and names its Android texture in the alpha byte, so it travels
 * unchanged through settings and Wyrm's arena skin sync:
 *   0xFE  nsk 0, AIR `kmc_ts[9][0]`  (plain bead)
 *   0xFD  nsk 1, AIR `kmc_ts[29][0]` (dark core, light rim)
 * Their atlas cells hold exact ports of those AIR bitmaps and of `ksmc_t`,
 * the outline and drop shadow AIR draws beneath each such bead. */
#define APPLE_AIR_SHADOW_SCALE (102.0f / 64.0f)

static int apple_air_kind(uint32_t rgba) {
  uint32_t tag = rgba >> 24;
  return tag == 0xFEu ? 0 : tag == 0xFDu ? 1 : -1;
}

static vec4s apple_air_bead_uv(int kind) {
  return (vec4s){{(2 + kind) / 7.0f, 6 / 9.0f, 1 / 7.0f, 1 / 9.0f}};
}

static vec4s apple_air_shadow_uv(void) {
  return (vec4s){{4 / 7.0f, 6 / 9.0f, APPLE_AIR_SHADOW_SCALE / 7.0f,
                  APPLE_AIR_SHADOW_SCALE / 9.0f}};
}

/* AIR setSkin: when mid + max channel is below nsk_min2c (255 for nsk 0 and
 * 1) every channel is lifted by 1 + (255 - (mid + max)) / 2, capped at 255,
 * then truncated by the `<< 16 | << 8 |` pack. */
static vec4s apple_air_tint(uint32_t rgba, float alpha) {
  float c[3] = {(float)((rgba >> 16) & 0xFF), (float)((rgba >> 8) & 0xFF),
                (float)(rgba & 0xFF)};
  float lo = fminf(c[0], fminf(c[1], c[2]));
  float hi = fmaxf(c[0], fmaxf(c[1], c[2]));
  float mid = c[0] + c[1] + c[2] - lo - hi;
  if (mid + hi < 255) {
    float lift = 1 + (255 - (mid + hi)) / 2;
    for (int i = 0; i < 3; ++i) c[i] = fminf(255, c[i] + lift);
  }
  for (int i = 0; i < 3; ++i) c[i] = floorf(c[i]);
  return (vec4s){{c[0] / 255.0f, c[1] / 255.0f, c[2] / 255.0f, alpha}};
}

static int apple_air_kind_at(tenv* env, snake* o, int point) {
  if (!o->cusk || o->cusk_len <= 0 || point < 0) return -1;
  uint32_t built = built_skin_rgba(env, o, point % o->cusk_len);
  return built ? apple_air_kind(built) : -1;
}

/* One `ksmc_t` stamp: unrotated, centred on the point, AIR's size. */
static void apple_air_shadow(tenv* env, int point, float half, float alpha,
                             float mww2, float mhh2) {
  game_data* gdata = &env->usr->gdata;
  float fix = (gdata->data.pbx[point] - gdata->data.view_xx) * gdata->data.gsc + mww2;
  float fiy = (gdata->data.pby[point] - gdata->data.view_yy) * gdata->data.gsc + mhh2;
  bp_renderer_push(env->usr->r->bpr,
                   &(bp_instance){{fix - half, fiy - half, 2 * half, 0},
                                  apple_air_shadow_uv(),
                                  {0, 0, 0, alpha}});
}

/* AIR's `_loc18_`: a shadow fades where consecutive stamps bunch up. */
static float apple_air_spacing(tenv* env, int point, float* sx, float* sy) {
  game_data* gdata = &env->usr->gdata;
  float ox = *sx, oy = *sy;
  *sx = gdata->data.pbx[point];
  *sy = gdata->data.pby[point];
  float d = fabsf(*sx - ox) + fabsf(*sy - oy);
  return fminf(1, d / 6);
}

'''

AIR_PREPASS = r'''            float shadow_strength = 0.25f;

            /* Wyrm iOS: AIR draws `ksmc_t` beneath every Build-a-Slither
               bead — the head's first nine fading out, then the tail's last
               four; the rest interleave with the body below, four points
               behind, exactly as AIR's redraw does. */
            const float apple_air_half =
                gdata->data.gsc * lsz * APPLE_AIR_SHADOW_SCALE;
            bool apple_air_any = false;
            for (int s = 0; o->cusk && s < o->cusk_len && !apple_air_any; ++s)
              apple_air_any = apple_air_kind_at(env, o, s) >= 0;
            float apple_air_sx = 31337357, apple_air_sy = 31337357;
            if (apple_air_any) {
              for (int p = bp - 1 < 8 ? bp - 1 : 8; p >= 0; p--)
                if (gdata->data.pbu[p] == 2 && apple_air_kind_at(env, o, p) >= 0)
                  apple_air_shadow(env, p, apple_air_half, a * (1 - p / 9.0f),
                                   mww2, mhh2);
              for (int n = 1; n <= 4; ++n) {
                int p = bp - n;
                if (p < 0 || gdata->data.pbu[p] != 2 ||
                    apple_air_kind_at(env, o, p) < 0)
                  continue;
                float spacing =
                    apple_air_spacing(env, p, &apple_air_sx, &apple_air_sy);
                if (n == 1) spacing = 1;
                apple_air_shadow(env, p, apple_air_half,
                                 spacing * a * (p < 9 ? p / 9.0f : 1), mww2,
                                 mhh2);
              }
            }'''

def apply_air_skin_render(text):
    anchor = '/* Food style is presentation only.'
    assert text.count(anchor) == 1
    text = text.replace(anchor, AIR_HELPERS + anchor, 1)

    start = text.index('          if (mode->render_mode == 0) {')
    end = text.index('          } else if (mode->render_mode == 1) {')
    chunk = text[start:end]

    prepass = '            float shadow_strength = 0.25f;'
    assert chunk.count(prepass) == 1
    chunk = chunk.replace(prepass, AIR_PREPASS, 1)

    # Wyrm's own tail shadows skip AIR beads, which have `ksmc_t` instead.
    tail = '''              for (j = start; j < bp; j++) {
                if (gdata->data.pbu[(int)j] >= 1) {'''
    assert chunk.count(tail) == 1
    chunk = chunk.replace(tail, '''              for (j = start; j < bp; j++) {
                if (gdata->data.pbu[(int)j] >= 1 &&
                    !(apple_air_any && apple_air_kind_at(env, o, (int)j) >= 0)) {''', 1)

    # Interleaved: the first such block in this chunk is the custom-skin one.
    interleave = '''                  if (j >= 4 && show_snake_shadows) {
                    k = j - 4;'''
    assert chunk.count(interleave) == 2
    chunk = chunk.replace(interleave, '''                  if (j >= 4 && apple_air_any &&
                      apple_air_kind_at(env, o, (int)j - 4) >= 0) {
                    int p = (int)j - 4;
                    if (gdata->data.pbu[p] == 2) {
                      float spacing = apple_air_spacing(env, p, &apple_air_sx,
                                                        &apple_air_sy);
                      apple_air_shadow(env, p, apple_air_half,
                                       spacing * a * (p < 9 ? p / 9.0f : 1),
                                       mww2, mhh2);
                    }
                  } else if (j >= 4 && show_snake_shadows) {
                    k = j - 4;''', 1)

    bead = '''                          built ? gdata->cg_uvs[BLANK_UV] : gdata->cg_uvs[cg_id],
                          built ? built_skin_color(built, a)
                                : (vec4s){{1, 1, 1, a}}});'''
    assert chunk.count(bead) == 1
    chunk = chunk.replace(bead, '''                          apple_air_kind(built) >= 0
                              ? apple_air_bead_uv(apple_air_kind(built))
                          : built ? gdata->cg_uvs[BLANK_UV]
                                  : gdata->cg_uvs[cg_id],
                          apple_air_kind(built) >= 0
                              ? apple_air_tint(built, a)
                          : built ? built_skin_color(built, a)
                                  : (vec4s){{1, 1, 1, a}}});''', 1)
    return text[:start] + chunk + text[end:]

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
        text = apply_air_skin_render(text)
    if relative == "app/src/game/arena_theme.c":
        text = text.replace("#include <jni.h>", "#ifdef __ANDROID__\n#include <jni.h>\n#endif")
        text = text.replace("JNIEXPORT void JNICALL", "#ifdef __ANDROID__\nJNIEXPORT void JNICALL", 1)
        text += "\n#endif\n"
    if relative == "app/src/main.c":
        text = text.replace('TDEF_ENTRY();', '')
        text = '#include "WyrmOriginalAdapter.h"\n' + text
        text = text.replace('  android_skin_poll(env);',
                            '  android_skin_poll(env);\n  WyrmIOSApplySkinSelection(env);\n  WyrmIOSArenaSyncPoll(env);')
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
            # The run receipt goes to SwiftUI's durable outbox, which posts it
            # to /v1/me/stats exactly as Android's Kotlin outbox does.
            'record_finished_run': '''extern void WyrmIOSRecordFinishedRun(int score, int kills);
  WyrmIOSRecordFinishedRun(env->usr->usrs.score, env->usr->usrs.kills);''',
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
        # Diagnostic only: record what the arena sends for another player's
        # custom skin, so whether an official Android (AIR) wheel skin reaches
        # a web-identity client with its RGB is settled by one capture. Bytes
        # and snake id only, no nickname; at most 24 per connection.
        skin_skip = '      m += skl;\n'
        assert text.count(skin_skip) == 1
        text = text.replace(skin_skip, '''      {
        static void* apple_skin_socket;
        static int apple_skin_logged;
        if (apple_skin_socket != (void*)gdata->connection) {
          apple_skin_socket = (void*)gdata->connection;
          apple_skin_logged = 0;
        }
        int shown = skl < 64 ? skl : 64;
        if (m + shown > alen) shown = alen - m;
        if (skl > 0 && shown > 0 && apple_skin_logged < 24) {
          char hex[64 * 2 + 1];
          for (int b = 0; b < shown; ++b)
            snprintf(hex + b * 2, 3, "%02X", (unsigned)a[m + b]);
          hex[shown * 2] = '\\0';
          SDL_Log("Wyrm arena skin id=%d len=%d bytes=%s", id, skl, hex);
          apple_skin_logged++;
        }
      }
''' + skin_skip)
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


# --- Image arrow skins (SourcesOriginal/AppleArrowSkins.c) -------------------
# Kept as its own pass after the main loop so it never interleaves with other
# adapters. The polygon arrow stays the engine's own; an image skin, when one is
# chosen, is drawn in its place with the geometry draw_arrow already computed.
def _arrow_patch(relative, pairs):
    target = OUTPUT / relative
    text = target.read_text(encoding="utf-8")
    for old, new in pairs:
        if old not in text:
            raise SystemExit(f"arrow skins: anchor missing in {relative}: {old[:60]!r}")
        text = text.replace(old, new, 1)
    target.write_text(text, encoding="utf-8")


_arrow_patch("app/src/rendering/renderer.c", [
    ("""  r->tags_descriptor = igImplVulkan_AddTexture(
      r->linear_sampler, r->tags_tex->view,
      VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL);
""", """  r->tags_descriptor = igImplVulkan_AddTexture(
      r->linear_sampler, r->tags_tex->view,
      VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL);
  {
    extern void WyrmIOSArrowSkinsCreate(renderer* r, tcontext* ctx);
    WyrmIOSArrowSkinsCreate(r, ctx);
  }
"""),
    ("""  if (r->tags_descriptor) igImplVulkan_RemoveTexture(r->tags_descriptor);
""", """  {
    extern void WyrmIOSArrowSkinsDestroy(tcontext* ctx);
    WyrmIOSArrowSkinsDestroy(ctx);
  }
  if (r->tags_descriptor) igImplVulkan_RemoveTexture(r->tags_descriptor);
"""),
])
_arrow_patch("app/src/mobile/mobile_controls.c", [
    ("""  float alpha = cfg->opacity * (env->usr->mobile_controls.arrow_opacity / 0.85f);
  mobile_arrow_shape shape = arrow_shape(env->usr->usrs.arrow_style);""",
     """  float alpha = cfg->opacity * (env->usr->mobile_controls.arrow_opacity / 0.85f);
  extern bool WyrmIOSDrawArrowImage(ImDrawList* dl, float ax, float ay, float dx,
                                    float dy, float length, float alpha);
  extern float WyrmIOSArrowBrightness(void);
  if (WyrmIOSDrawArrowImage(dl, ax, ay, dx, dy, length, alpha)) return;
  float wyrm_brightness = WyrmIOSArrowBrightness();
  mobile_arrow_shape shape = arrow_shape(env->usr->usrs.arrow_style);"""),
    ("""  ImU32 fill =
      color_u32(arrow->color[0], arrow->color[1], arrow->color[2], alpha);""",
     """  ImU32 fill = color_u32(arrow->color[0] * wyrm_brightness,
                         arrow->color[1] * wyrm_brightness,
                         arrow->color[2] * wyrm_brightness, alpha);"""),
])
print("Arrow skins: renderer atlas and draw_arrow hook applied")
