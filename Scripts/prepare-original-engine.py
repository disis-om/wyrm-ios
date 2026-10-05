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

# The bounded custom-skin encoder for the join (arena drop fix, 2026-09-29);
# the same C as Wyrm Android's network/callback.c.
NEW_SKIN_ENCODER = r'''/*
 * How many (count, colour) runs a join may carry: NTL's limit. NTL cuts its
 * skin block to 300 bytes (`cb.slice(0,300)` in main-mt.js), which is the
 * 8-byte header plus 146 pairs, and arenas take that from NTL players every
 * day. Live, one arena (OM, 2026-09-29/30): skin blocks of 102, 200, 256, 300
 * and 400 bytes were admitted; 500 bytes (a 533-540-byte join) closed the
 * socket before configuration. That 500-byte block was the arena drop.
 */
#define WYRM_JOIN_SKIN_MAX_RUNS 146

/* The colours the official client lets a custom skin use. */
static bool skin_colour_allowed(int cg) {
  return (cg >= 0 && cg <= 35) || cg == 37 || cg == 39 || cg == 41;
}

/*
 * The run list for the join: official colours only, one repeat of the
 * pattern, at most WYRM_JOIN_SKIN_MAX_RUNS runs. The arena repeats a pattern
 * along the body, so one repeat looks the same to everyone else; iOS hands
 * over its motif repeated to 256 beads, and this folds that back. Our own
 * snake still draws the whole design (see the own-snake block in 's').
 * Empty when nothing valid is left: the join then goes out as a preset one.
 */
uint8_t* get_skin_compressed(tuser_data* usr) {
  user_settings* usrs = &usr->usrs;
  uint8_t* reduced = tdarray_create(uint8_t);

  uint8_t groups[MAX_SKIN_CODE_LEN];
  int count = 0;
  for (int i = 0; i < MAX_SKIN_CODE_LEN && usrs->skin_code[i]; i++) {
    int cg = get_cg_id(&usr->gdata, usrs->skin_code[i]);
    if (skin_colour_allowed(cg)) groups[count++] = (uint8_t)cg;
  }
  if (!count) return reduced;

  /* The smallest period p with groups[i] == groups[i - p] for every i >= p.
     Below 256 beads p must also divide the pattern: the arena repeats what
     it is sent, so folding "abcdefga" to "abcdefg" dropped the last bead from
     every repeat (OM, 2026-10-04; until then any p was taken). A full 256
     (iOS hands over its motif repeated to 256) may end part-way through a
     repeat, so there any p is still taken. */
  int period = count;
  for (int p = 1; p < count; p++) {
    if (count % p != 0 && count != MAX_SKIN_CODE_LEN) continue;
    bool repeats = true;
    for (int i = p; i < count; i++) {
      if (groups[i] != groups[i - p]) {
        repeats = false;
        break;
      }
    }
    if (repeats) {
      period = p;
      break;
    }
  }

  int runs = 0;
  int i = 0;
  while (i < period && runs < WYRM_JOIN_SKIN_MAX_RUNS) {
    uint8_t cg = groups[i];
    int n = 1;
    while (i + n < period && groups[i + n] == cg && n < UINT8_MAX) n++;
    uint8_t run = (uint8_t)n;
    tdarray_push(&reduced, &run);
    tdarray_push(&reduced, &cg);
    runs++;
    i += n;
  }
  if (i < period)
    SDL_Log("Wyrm arena: custom skin trimmed for the join — %d of %d beads "
            "in one repeat, %d stripes", i, period, runs);
  return reduced;
}
'''
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

# Performance (OM, 2026-10-01; Wyrm Android's main.c has the same gate): the
# engine draws only where it can be seen (lobby, match, skin editor, the Skin
# postcard). Under the opaque SwiftUI pages it draws a few settle frames and
# then stops, while every poll in trender keeps running. The old Vlither
# background for screens that no longer exist goes too.
RENDER_GATE = r"""
/*
 * Performance (OM, 2026-10-01): the engine draws only where it can be seen.
 *
 * Home, Social, Settings and every other Compose / SwiftUI page are opaque,
 * and the engine used to draw a whole frame under them every pass anyway. Now
 * it draws in the lobby, in a match (the AI editors are matches), in the skin
 * editor and for the Skin postcard. Leaving those, it draws a few settle
 * frames, so what stays on the surface is the plain clear colour and never a
 * stale arena, and then stops drawing. The polls at the top of trender still
 * run every pass, so mailboxes, settings and the socket behave exactly as
 * before. Nothing here reads or writes the protocol or the game.
 */
#define WYRM_SETTLE_FRAMES 4
static int wyrm_settle = WYRM_SETTLE_FRAMES;

static bool wyrm_engine_visible(tenv* env) {
  /* Until a frame has reached the screen (start, a new surface), keep drawing. */
  if (!env->ctx->last_present_succeeded) return true;
  if (env->usr->gdata.curr_screen != TITLE_SCREEN || ui_skin_editor_postcard()) {
    wyrm_settle = WYRM_SETTLE_FRAMES;
    return true;
  }
  if (wyrm_settle > 0) {
    wyrm_settle--;
    return true;
  }
  return false;
}

"""


def apply_render_gate(text):
    nl = "\r\n" if "\r\n" in text else "\n"
    pairs = [
        ("void trender(tenv* env) {\n", RENDER_GATE + "void trender(tenv* env) {\n"),
        ("""  if (usr->gdata.curr_screen != PLAYING &&
      usr->gdata.curr_screen != SKIN_EDITOR &&
      usr->gdata.curr_screen != TITLE_SCREEN &&
      usr->gdata.curr_screen != LOBBY) {
    ui_theme_draw_background(env);
    ui_theme_draw_version(env);
  }
""", ""),
        ("""  igRender();
  if (tcontext_begin(ctx)) {""", """  igRender();
  bool draw = wyrm_engine_visible(env);
  if (draw && tcontext_begin(ctx)) {"""),
        ("""void tresize(tenv* env) {
  ui_viewport_resize(env);""", """void tresize(tenv* env) {
  ui_viewport_resize(env);
  /* A new swapchain starts empty: give it the settle frames again. */
  wyrm_settle = WYRM_SETTLE_FRAMES;"""),
    ]
    for old, new in pairs:
        old, new = old.replace("\n", nl), new.replace("\n", nl)
        if text.count(old) != 1:
            raise SystemExit(f"render gate: anchor missing in main.c: {old[:60]!r}")
        text = text.replace(old, new, 1)
    return text


# Wyrm's own floors (OM, 2026-10-01; Wyrm Android's backgrounds.h has the same
# rows): Black (assist mode's true black, for any mode) and seven seamless
# tiles from Resources/Backgrounds. The list lives in Scripts/wyrm_backgrounds.py.
import sys as _sys
_sys.path.insert(0, str(ROOT / "Scripts"))
from wyrm_backgrounds import EXTRA_BACKGROUNDS, BLACK_INDEX, engine_row


def apply_wyrm_backgrounds_table(text):
    nl = "\r\n" if "\r\n" in text else "\n"
    pairs = [
        ("  BACKGROUND_NONE = 1,\n", f"  BACKGROUND_NONE = 1,\n  BACKGROUND_BLACK = {BLACK_INDEX},\n"),
        ('    {"redcube", "Red cube", "app/res/textures/backgrounds/bg_redcube.png", 872.0f, 882.0f},\n',
         '    {"redcube", "Red cube", "app/res/textures/backgrounds/bg_redcube.png", 872.0f, 882.0f},\n'
         + "".join(engine_row(*row) + "\n" for row in EXTRA_BACKGROUNDS)),
    ]
    for old, new in pairs:
        old, new = old.replace("\n", nl), new.replace("\n", nl)
        if text.count(old) != 1:
            raise SystemExit(f"backgrounds: anchor missing in backgrounds.h: {old[:60]!r}")
        text = text.replace(old, new, 1)
    return text


def apply_wyrm_backgrounds_redraw(text):
    nl = "\r\n" if "\r\n" in text else "\n"
    pairs = [
        ('''  usr->r->global.bg_opacity =
      background_clamp(usrs->arena_background) == BACKGROUND_NONE ? 0.0f : 1.0f;''',
         '''  const int floor_index = background_clamp(usrs->arena_background);
  usr->r->global.bg_opacity = floor_index == BACKGROUND_NONE ? 0.0f : 1.0f;'''),
        ('''  usr->r->global.bg_color[0] = usr->r->global.bg_color[1] =
      usr->r->global.bg_color[2] = mode->show_background;''',
         '''  /* Black is drawn the way assist mode's hidden floor is: no colour, full
     opacity, so it is true black in either mode. */
  usr->r->global.bg_color[0] = usr->r->global.bg_color[1] =
      usr->r->global.bg_color[2] =
          floor_index == BACKGROUND_BLACK ? 0.0f : (float)mode->show_background;'''),
    ]
    for old, new in pairs:
        old, new = old.replace("\n", nl), new.replace("\n", nl)
        if text.count(old) != 1:
            raise SystemExit(f"backgrounds: anchor missing in redraw.c: {old[:60]!r}")
        text = text.replace(old, new, 1)
    return text


def apply_wyrm_backgrounds_skin_editor(text):
    nl = "\r\n" if "\r\n" in text else "\n"
    old = '''               : (background_clamp(usrs->arena_background) == BACKGROUND_NONE
                      ? 0.0f
                      : 0.55f);'''
    new = '''               : (background_clamp(usrs->arena_background) == BACKGROUND_NONE ||
                          background_clamp(usrs->arena_background) == BACKGROUND_BLACK
                      ? 0.0f
                      : 0.55f);'''
    old, new = old.replace("\n", nl), new.replace("\n", nl)
    if text.count(old) != 1:
        raise SystemExit("backgrounds: anchor missing in skin_editor.c")
    return text.replace(old, new, 1)


def copy_wyrm_backgrounds():
    target = OUTPUT / "app/res/textures/backgrounds"
    target.mkdir(parents=True, exist_ok=True)
    for _key, _label, file, _w, _h in EXTRA_BACKGROUNDS:
        if file is None:
            continue
        source = ROOT / "Resources" / "Backgrounds" / file
        if not source.exists():
            raise SystemExit(f"backgrounds: Resources/Backgrounds/{file} is missing")
        shutil.copyfile(source, target / file)


# The slither.io Android (AIR) Build-a-Slither beads. The atlas below is the
# original one plus three cells written by Scripts/generate-air-skin-assets.py
# (exact ports of AIR's nsk 0/1 bead bitmaps and its `ksmc_t` shadow, checked
# against the baked AIR sheets). Both hashes are pinned so neither can drift.
ORIGINAL_ATLAS_SHA256 = "73805db544b97b51c3ce7d898dbc48d5ea2bc173dcd402e072f0c63642342fed"
AIR_ATLAS = ROOT / "Resources" / "AirSkin" / "tex_atlas_8k.png"
AIR_ATLAS_SHA256 = "6a1d2a4491ed17f31dc5585b5a68ede85e48592d5a7ed032e976148886eea753"
atlas_target = OUTPUT / "app/res/textures/tex_atlas_8k.png"
if hashlib.sha256(atlas_target.read_bytes()).hexdigest() != ORIGINAL_ATLAS_SHA256:
    raise SystemExit("Original atlas changed; regenerate Resources/AirSkin")
if hashlib.sha256(AIR_ATLAS.read_bytes()).hexdigest() != AIR_ATLAS_SHA256:
    raise SystemExit("Resources/AirSkin/tex_atlas_8k.png does not match its pinned hash")
shutil.copyfile(AIR_ATLAS, atlas_target)
copy_wyrm_backgrounds()

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
/* Off (OM, 2026-09-28): the `ksmc_t` stamps read as a black shadow wrapped
 * round the whole snake, which beads picked from the grid never had. With it
 * off, wheel beads get the same shadows as every other bead. 1 restores AIR. */
#define WYRM_AIR_BEAD_SHADOW 0

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
            for (int s = 0; WYRM_AIR_BEAD_SHADOW && o->cusk && s < o->cusk_len && !apple_air_any; ++s)
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

WYRM_BEAD_HELPERS = r'''/* Wyrm's own beads (OM, 2026-09-28). A built segment whose alpha byte is
 * 0xE0 + k (beads 0-23) or 0xC0 + k - 24 (beads 24-53) wears Wyrm bead k,
 * painted by Wyrm iOS Scripts/generate-wyrm-beads.py into six atlas cells
 * nothing else samples (row 7 cols 3 and 6, row 8 cols 0-3), nine to a cell
 * in a 3 x 3 grid. Every bead is drawn in its own painted colours; the RGB
 * only picks the arena's nearest colour group. Like every slither bead, the
 * motif sits on the +x side, the side a body drawn tail first leaves showing. */
#define WYRM_BEAD_TAG 0xE0u
#define WYRM_BEAD_TAG2 0xC0u
#define WYRM_BEAD_FIRST_COUNT 24
#define WYRM_BEAD_COUNT 54

static const unsigned char wyrm_bead_cells[WYRM_BEAD_COUNT / 9][2] = {
    {7, 3}, {7, 6}, {8, 0}, {8, 1}, {8, 2}, {8, 3}};

static int wyrm_bead_kind(uint32_t rgba) {
  uint32_t tag = rgba >> 24;
  if (tag >= WYRM_BEAD_TAG && tag < WYRM_BEAD_TAG + WYRM_BEAD_FIRST_COUNT)
    return (int)(tag - WYRM_BEAD_TAG);
  if (tag >= WYRM_BEAD_TAG2 &&
      tag < WYRM_BEAD_TAG2 + (WYRM_BEAD_COUNT - WYRM_BEAD_FIRST_COUNT))
    return (int)(tag - WYRM_BEAD_TAG2) + WYRM_BEAD_FIRST_COUNT;
  return -1;
}

static vec4s wyrm_bead_uv(int kind) {
  const unsigned char* cell = wyrm_bead_cells[kind / 9];
  float qx = (float)(kind % 3) / 3.0f, qy = (float)((kind % 9) / 3) / 3.0f;
  return (vec4s){{(cell[1] + qx) / 7.0f, (cell[0] + qy) / 9.0f,
                  (1.0f / 3.0f) / 7.0f, (1.0f / 3.0f) / 9.0f}};
}

static vec4s wyrm_bead_color(uint32_t rgba, int kind, float alpha) {
  (void)rgba;
  (void)kind;
  return (vec4s){{1, 1, 1, alpha}};
}

'''

WYRM_BEAD_COLOR_OLD = r'''/** The packed colour above, as the renderer's own RGBA. */
static vec4s built_skin_color(uint32_t rgba, float alpha_scale) {
  return (vec4s){{((rgba >> 16) & 0xFF) / 255.0f, ((rgba >> 8) & 0xFF) / 255.0f,
                  (rgba & 0xFF) / 255.0f,
                  ((rgba >> 24) & 0xFF) / 255.0f * alpha_scale}};
}'''

WYRM_BEAD_COLOR_NEW = r'''/** The packed colour above, as the renderer's own RGBA. A Wyrm bead's alpha
 * byte names its texture, so where it is drawn as a plain colour (the flat
 * render mode) it is opaque. */
static vec4s built_skin_color(uint32_t rgba, float alpha_scale) {
  float alpha = wyrm_bead_kind(rgba) >= 0 ? 1.0f : ((rgba >> 24) & 0xFF) / 255.0f;
  return (vec4s){{((rgba >> 16) & 0xFF) / 255.0f, ((rgba >> 8) & 0xFF) / 255.0f,
                  (rgba & 0xFF) / 255.0f, alpha * alpha_scale}};
}'''


def apply_air_skin_render(text):
    # Wyrm's own beads: helpers before `built_skin_color`, which must keep a
    # bead's tag byte from reading as transparency. Kept byte-equal with Android.
    assert text.count(WYRM_BEAD_COLOR_OLD) == 1
    text = text.replace(WYRM_BEAD_COLOR_OLD, WYRM_BEAD_HELPERS + WYRM_BEAD_COLOR_NEW, 1)

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
    chunk = chunk.replace(bead, '''                          wyrm_bead_kind(built) >= 0
                              ? wyrm_bead_uv(wyrm_bead_kind(built))
                          : apple_air_kind(built) >= 0
                              ? apple_air_bead_uv(apple_air_kind(built))
                          : built ? gdata->cg_uvs[BLANK_UV]
                                  : gdata->cg_uvs[cg_id],
                          wyrm_bead_kind(built) >= 0
                              ? wyrm_bead_color(built, wyrm_bead_kind(built), a)
                          : apple_air_kind(built) >= 0
                              ? apple_air_tint(built, a)
                          : built ? built_skin_color(built, a)
                                  : (vec4s){{1, 1, 1, a}}});''', 1)
    return text[:start] + chunk + text[end:]


# "Share this run" (OM, 2026-09-30): a one-frame swapchain readback when a run
# is recorded. SourcesOriginal/AppleRunCapture.inc is appended to tcontext.c;
# the frame path gains five calls and none of them waits on the GPU.
RUN_CAPTURE_PROTOTYPES = r'''#include "tcontext.h"

/* Wyrm iOS run screenshots; defined in AppleRunCapture.inc (appended). */
static VkImageUsageFlags wyrm_capture_usage(tcontext* context,
                                            VkImageUsageFlags supported);
static void wyrm_capture_refused(VkResult result);
static void wyrm_capture_record(tcontext* context);
static void wyrm_capture_submitted(tcontext* context, bool submitted);
static void wyrm_capture_harvest(tcontext* context);
static void wyrm_capture_release(tcontext* context);
'''


SWAPCHAIN_REBUILD_PAIRS = [('''  free(context->swapchain_frames);

  _tcontext_create_swapchain(context, vsync);
  if (context->swapchain == VK_NULL_HANDLE) {
    context->swapchain_ok = false;
    context->old_swapchain = VK_NULL_HANDLE;
    return;
  }''', '''  free(context->swapchain_frames);
  /* Nothing is left to destroy until the views are built again. A failed
     rebuild used to keep the freed array and the old count, so the recovery
     resize destroyed those views a second time (iOS crash reports
     2026-10-03, vkDestroyImageView from tcontext_resize at launch). */
  context->swapchain_frames = NULL;
  context->image_count = 0;

  _tcontext_create_swapchain(context, vsync);
  if (context->swapchain == VK_NULL_HANDLE) {
    context->swapchain_ok = false;
    /* The failed call retired the old swapchain; free it so the next attempt
       starts on a clear surface. */
    if (context->old_swapchain != VK_NULL_HANDLE)
      vkDestroySwapchainKHR(context->device, context->old_swapchain, NULL);
    context->old_swapchain = VK_NULL_HANDLE;
    return;
  }''')]


# Web persona only (OM, 2026-10-04): the AIR identity is removed. These are
# Wyrm Android's network/arena_persona.h and .c, byte for byte, written over
# the pinned SharedEngine copies; WEB_ONLY_PAIRS take the AIR branches out
# of callback.c. Revert: delete these constants and their two uses below.
WEB_PERSONA_H = r'''#ifndef ARENA_PERSONA_H
#define ARENA_PERSONA_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

/*
 * Which slither client Wyrm claims to be on the wire: the web client only
 * (`game1107241958.js`, version 291), byte for byte as Vlither sends it.
 *
 * Wyrm used to carry a second identity, the Android AIR client (version 294,
 * its own fingerprint, a CRC32 challenge answer and a settings `c` packet),
 * and could switch to it. It was removed on 2026-10-04 (OM): every arena
 * report showed the web identity, and on `148.113.20.151` the AIR identity was
 * hung up on before the arena said anything. The removed code is in git
 * history (Android 6.4.2, iOS build 95).
 */
typedef struct arena_persona {
  /* Goes in every arena log line. */
  const char* name;
  /* Bytes 2..3 of the join packet. */
  uint16_t version;
  /* Bytes 4..23 of the join packet. */
  uint8_t fingerprint[20];
} arena_persona;

enum {
  ARENA_PERSONA_WEB = 0,
  NUM_ARENA_PERSONAS = 1
};

/** The web client, whatever `index` says: a settings file written by a build
    that could still switch to AIR (index 1) joins as the web client too. */
const arena_persona* arena_persona_get(int index);

#endif
'''
WEB_PERSONA_C = r'''#include "arena_persona.h"

/* The web client's identity: `client_version` and `cpw` in game1107241958.js,
   the same as Vlither's CLIENT_VERSION and `cwa`. */
static const arena_persona web = {.name = "web",
                                  .version = 291,
                                  .fingerprint = {54, 206, 204, 169, 97, 178,
                                                  74, 136, 124, 117, 14, 210,
                                                  106, 236, 8, 208, 136, 213,
                                                  140, 111}};

const arena_persona* arena_persona_get(int index) {
  (void)index;
  return &web;
}
'''
WEB_ONLY_PAIRS = [(r'''    /* Two clients, two answers to the same challenge. The web packet is the
       obfuscated program which produces its per-connection answer; the visible
       `gotServerVersion` stub is not that answer. `decode_secret` executes the
       packet's fixed transformation byte-for-byte. The AIR client instead uses
       the CRC32 path compiled into that store binary. */
    if (persona->crc32_answer) {
      uint8_t answer[ARENA_CRC32_ANSWER_LEN];
      size_t answer_len = arena_persona_crc32_answer(a, a_len, answer);
      arena_send(c, answer, answer_len);
    } else {
      uint8_t answer[27];
      decode_secret(a, (size_t)a_len, answer);
      arena_send(c, answer, sizeof(answer));
      SDL_Log("Wyrm arena: web challenge answer 0x%02X..0x%02X (decoded packet)",
              answer[0], answer[26]);
    }''', r'''    /* The web client's answer. The challenge packet is the obfuscated program
       which produces its per-connection answer; the visible `gotServerVersion`
       stub is not that answer. `decode_secret` executes the packet's fixed
       transformation byte-for-byte. (The AIR client's CRC32 answer was removed
       with that identity, 2026-10-04.) */
    {
      uint8_t answer[27];
      decode_secret(a, (size_t)a_len, answer);
      arena_send(c, answer, sizeof(answer));
      SDL_Log("Wyrm arena: web challenge answer 0x%02X..0x%02X (decoded packet)",
              answer[0], answer[26]);
    }'''),
                  (r'''    const arena_persona* persona = arena_persona_get(gdata->persona);
    if (persona->full_c_packet) {
      user_settings* usrs = &usr->usrs;
      uint8_t cp[16];
      int n = 0;
      cp[n++] = 'c';
      cp[n++] = 1;   /* not a team join */
      cp[n++] = 2;   /* platform: Android */
      /* Wyrm steers by relative drag, which is the AIR client's arrow mode. */
      cp[n++] = 2;
      cp[n++] = usrs->mobile_controls.boost_mode ? 1 : 0;
      cp[n++] = 0;   /* controls are not flipped */
      cp[n++] = usrs->hotkeys[HOTKEY_SHOW_NAMES].active ? 1 : 0;
      cp[n++] = 1;   /* high quality */
      cp[n++] = 0;   /* minimap is not pinned top-left */
      cp[n++] = 0;   /* no named background: Wyrm draws its own */
      cp[n++] = 0;   /* no look-ahead camera */
      cp[n++] = 1;   /* the nickname is saved */
      arena_send(c, cp, n);
    } else {
      arena_send(c, (uint8_t[]){'c', 0}, 2);
    }''', r'''    /* The web client's `63 00`. (The AIR client's settings block was removed
       with that identity, 2026-10-04.) */
    arena_send(c, (uint8_t[]){'c', 0}, 2);''')]



# NTL's tag in the skin block (OM, 2026-10-04): the same C as Wyrm Android's
# network/callback.c, game/snake.h, game/tags.c and network/ntl_net.c,
# byte for byte (free tags 254/18, public 255/38 in bytes 0, 1, 2 and 6 of
# the join's skin block, read back from other snakes as NTL 9.68 reads
# them). Revert: delete this constant and its use below.
NTL_SKIN_TAG_PAIRS = {
    'app/src/network/callback.c': [
        (r'''#include "../game/snake.h"
''',
         r'''#include "../game/snake.h"
#include "../game/tags.h"
'''),
        (r'''/*
 * The snake this player is steering, or nothing at all.
''',
         r'''/*
 * NTL's tag in the skin block (OM, 2026-10-04), byte for byte as NTL 9.68
 * writes it (`legacy/ntl 9.68/main-mt.js`, the join builder) and reads it
 * (its skin setup `rn`). The arena relays the block untouched and the
 * official client reads only the runs from byte 8 on, so these first bytes
 * are how every NTL player, and now every Wyrm player, shows a tag to
 * everyone without a team:
 *
 *   free tags 0..59:      254, 18, skin, 0, 0, 0, tag,       0
 *   public tags 200..367: 255, 38, skin, 0, 0, 0, tag - 200, 0
 *   public tags 668..755: 255, 38, skin, 0, 0, 0, tag - 500, 0
 *
 * `skin` is 255 for a custom skin, else the preset. A preset that wears a tag
 * goes out as a block too, with NTL's own runs for that preset (`Ff`), and
 * NTL draws such a snake as the preset in byte 2. NTL's claimed private tags
 * (60..199, 368..665, 756 on) travel on the tag socket with their password
 * instead (ntl_net.c); Wyrm has none of their artwork. Without a tag the
 * block is exactly what it was. Revert: the Wyrm Android AGENTS.md Log entry
 * of 2026-10-04 "NTL tag corner".
 */
#define NTL_TAG_FREE_MARK 254   /* byte 0 of a free tag */
#define NTL_TAG_FREE_KIND 18    /* byte 1 of a free tag: NTL's `tn` */
#define NTL_TAG_PUBLIC_MARK 255 /* byte 0 of a public tag */
#define NTL_TAG_PUBLIC_KIND 38  /* byte 1 of a public tag */
#define NTL_TAG_FREE_COUNT 60   /* NTL's `PA`: its 60 bundled tags */
#define NTL_PRESET_COUNT 66

/* NTL's `Ff`: every preset as (count, colour) runs. */
static const uint8_t NTL_PRESET_RUNS[NTL_PRESET_COUNT][24] = {
  {1, 0},
  {1, 1},
  {1, 2},
  {1, 3},
  {1, 4},
  {1, 5},
  {1, 6},
  {1, 7},
  {1, 8},
  {1, 7, 1, 9, 1, 7, 1, 9, 1, 7, 1, 9, 1, 7, 1, 9, 1, 7, 1, 9, 1, 7, 9, 10},
  {5, 9, 5, 1, 5, 7},
  {5, 11, 5, 7, 5, 12},
  {5, 7, 5, 9, 5, 13},
  {5, 14, 5, 9, 5, 7},
  {7, 9, 7, 7},
  {1, 0, 1, 1, 1, 2, 1, 3, 1, 4, 1, 5, 1, 6, 1, 7, 1, 8},
  {7, 15, 7, 4},
  {7, 9, 7, 16},
  {7, 7, 7, 9},
  {1, 9},
  {5, 3, 5, 0},
  {7, 3, 6, 18, 1, 20, 1, 19, 1, 20, 1, 19, 1, 20, 1, 19, 1, 20, 6, 18},
  {7, 5, 7, 9, 7, 13},
  {7, 16, 7, 18, 7, 7},
  {9, 23, 9, 18},
  {12, 21, 9, 22},
  {1, 24},
  {1, 25},
  {7, 18, 7, 25, 7, 7},
  {2, 11, 1, 4, 4, 11, 1, 4, 2, 11},
  {2, 10, 1, 19, 1, 20, 2, 10, 1, 20, 1, 19},
  {2, 10},
  {2, 20},
  {1, 12, 2, 11},
  {2, 7, 1, 9, 2, 13, 1, 9, 2, 16, 1, 9, 2, 12, 1, 9, 2, 7, 1, 9, 2, 16, 1, 9},
  {2, 7, 2, 9, 2, 6, 2, 9},
  {2, 16, 2, 9, 2, 15, 2, 9},
  {1, 22},
  {1, 18},
  {1, 23},
  {1, 26},
  {1, 27},
  {8, 2, 8, 3, 8, 5, 8, 7},
  {1, 28},
  {1, 29},
  {3, 7, 8, 9, 3, 7},
  {1, 7},
  {3, 16, 8, 18, 7, 7, 4, 16},
  {1, 7},
  {4, 23, 8, 9, 2, 23},
  {14, 18, 7, 16, 7, 7},
  {3, 7, 2, 9, 6, 16, 2, 9},
  {4, 7, 9, 18, 5, 7},
  {1, 30},
  {1, 31},
  {1, 32},
  {1, 33},
  {1, 34},
  {1, 35},
  {1, 18},
  {1, 36},
  {6, 30, 6, 35, 6, 33, 6, 31, 6, 32, 6, 34},
  {5, 17, 5, 39},
  {3, 7, 3, 11},
  {2, 16, 2, 11},
  {4, 4, 4, 9},
};
static const uint8_t NTL_PRESET_RUN_BYTES[NTL_PRESET_COUNT] = {
  2, 2, 2, 2, 2, 2, 2, 2, 2, 24, 6, 6, 6, 6, 4, 18, 4, 4, 4, 2, 4, 20, 6, 6, 4, 4, 2, 2, 6, 10, 12, 2, 2, 4, 24, 8, 8, 2, 2, 2, 2, 2, 8, 2, 2, 6, 2, 8, 2, 6, 6, 8, 6, 2, 2, 2, 2, 2, 2, 2, 2, 12, 4, 4, 4, 4};

/* NTL's `xA`: presets the official client draws with an antenna of their
   own, and which tag that is. Wearing exactly that tag on that preset, NTL
   sends no block (its `HA`), so the official antenna stays for everyone. */
static const struct {
  uint8_t skin;
  int16_t tag;
} NTL_PRESET_TAGS[] = {{24, 14}, {25, 13}, {27, -1}, {37, 1}, {39, 5}, {40, -1}, {41, -1}, {42, 4}, {45, 0}, {46, 3}, {47, 7}, {48, 2}, {49, 10}, {59, 6}, {62, 8}, {65, 39}};

/* Bytes 0, 1 and 6 of the corner for an NTL tag number; false for a tag that
   does not travel in the block. */
static bool ntl_tag_corner(int ntl, uint8_t* mark, uint8_t* kind,
                           uint8_t* tag) {
  if (ntl > 199 && ntl < 368) {
    *mark = NTL_TAG_PUBLIC_MARK;
    *kind = NTL_TAG_PUBLIC_KIND;
    *tag = (uint8_t)(ntl - 200);
    return true;
  }
  if (ntl > 667 && ntl < 756) {
    *mark = NTL_TAG_PUBLIC_MARK;
    *kind = NTL_TAG_PUBLIC_KIND;
    *tag = (uint8_t)(ntl - 500);
    return true;
  }
  if (ntl >= 0 && ntl < NTL_TAG_FREE_COUNT) {
    *mark = NTL_TAG_FREE_MARK;
    *kind = NTL_TAG_FREE_KIND;
    *tag = (uint8_t)ntl;
    return true;
  }
  return false;
}

/* Whether a preset already wears this tag as its official antenna. */
static bool ntl_preset_wears(int skin, int ntl) {
  for (size_t i = 0; i < sizeof(NTL_PRESET_TAGS) / sizeof(NTL_PRESET_TAGS[0]);
       i++)
    if (NTL_PRESET_TAGS[i].skin == skin) return NTL_PRESET_TAGS[i].tag == ntl;
  return false;
}

/* The NTL tag number a received block's corner names, or -1. */
static int ntl_tag_from_corner(const uint8_t* corner) {
  if (corner[1] == NTL_TAG_FREE_KIND)
    return corner[0] == NTL_TAG_FREE_MARK && corner[6] < NTL_TAG_FREE_COUNT
               ? corner[6]
               : -1;
  if (corner[1] == NTL_TAG_PUBLIC_KIND)
    return corner[6] < 168 ? corner[6] + 200 : corner[6] + 500;
  return -1;
}

/*
 * The snake this player is steering, or nothing at all.
'''),
        (r'''    ba = malloc(8 + 20 + nick_len + (skin_compressed ? 8 + skin_compressed_len : 0));
''',
         r'''    /* NTL's tag corner (see ntl_tag_corner). A preset wearing a tag goes out
       with NTL's block for that preset, unless the preset already wears that
       very tag as its official antenna: then NTL sends no block either. */
    uint8_t tag_mark = 0, tag_kind = 0, tag_byte = 0;
    int worn_ntl = tags_valid(usrs->tag_index) ? tags_ntl_id(usrs->tag_index) : -1;
    bool tag_corner =
        web_persona && ntl_tag_corner(worn_ntl, &tag_mark, &tag_kind, &tag_byte);
    bool preset_block = false;
    if (tag_corner && !skin_compressed &&
        (usrs->default_skin >= NTL_PRESET_COUNT ||
         !ntl_preset_wears(usrs->default_skin, worn_ntl))) {
      int preset = usrs->default_skin % NTL_PRESET_COUNT;
      skin_compressed = tdarray_create(uint8_t);
      for (int i = 0; i < NTL_PRESET_RUN_BYTES[preset]; i++) {
        uint8_t run_byte = NTL_PRESET_RUNS[preset][i];
        tdarray_push(&skin_compressed, &run_byte);
      }
      skin_compressed_len = NTL_PRESET_RUN_BYTES[preset];
      preset_block = true;
    }
    if (!skin_compressed) tag_corner = false;
    ba = malloc(8 + 20 + nick_len + (skin_compressed ? 8 + skin_compressed_len : 0));
'''),
        (r'''    if (skin_compressed) {
      ba[m++] = 255;
      ba[m++] = 255;
      ba[m++] = 255;
      ba[m++] = 0;
      ba[m++] = 0;
      ba[m++] = 0;
      ba[m++] = rand() % 256;
      ba[m++] = rand() % 256;
''',
         r'''    if (skin_compressed) {
      int corner = m;
      ba[m++] = 255;
      ba[m++] = 255;
      ba[m++] = 255;
      ba[m++] = 0;
      ba[m++] = 0;
      ba[m++] = 0;
      ba[m++] = rand() % 256;
      ba[m++] = rand() % 256;
      if (tag_corner) {
        /* NTL's header is 255 255 255 0 0 0 0 0 (`Zf`) with bytes 0, 1, 2
           and 6 written over; byte 7 stays 0. */
        ba[corner + 0] = tag_mark;
        ba[corner + 1] = tag_kind;
        ba[corner + 2] = preset_block ? usrs->default_skin : 255;
        ba[corner + 6] = tag_byte;
        ba[corner + 7] = 0;
        SDL_Log("Wyrm arena: NTL tag %d in the skin corner (%s block, %d run bytes)",
                worn_ntl, preset_block ? "preset" : "custom", skin_compressed_len);
      }
'''),
        (r'''      int skl = gdata->data.protocol_version >= 11 ? a[m++] : 0;
      if (skl > 0) {
''',
         r'''      int skl = gdata->data.protocol_version >= 11 ? a[m++] : 0;
      /* NTL's tag corner (see ntl_tag_corner), read as NTL reads it: the tag,
         and for NTL's two kinds a preset in byte 2 that NTL draws instead of
         the runs (255: the runs are the skin). */
      int corner_tag = -1;
      int corner_preset = -1;
      if (skl >= 8 && m + 8 <= alen) {
        corner_tag = ntl_tag_from_corner(a + m);
        if ((a[m + 1] == NTL_TAG_FREE_KIND || a[m + 1] == NTL_TAG_PUBLIC_KIND) &&
            a[m + 2] != 255)
          corner_preset = a[m + 2];
      }
      if (skl > 0) {
'''),
        (r'''      o.cv = cv % NUM_DEFAULT_SKINS;
      o.cusk = skl != 0;
''',
         r'''      o.cv = cv % NUM_DEFAULT_SKINS;
      o.cusk = skl != 0;
      /* A corner naming a preset: that preset, as NTL draws it (the runs are
         only the official client's copy of it). */
      if (corner_preset >= 0) {
        o.cv = corner_preset % NUM_DEFAULT_SKINS;
        o.cusk = false;
        o.cusk_len = 0;
      }
      o.skin_tag = corner_tag >= 0 ? tags_from_ntl_id(corner_tag) + 1 : 0;
'''),
    ],
    'app/src/game/snake.h': [
        (r'''  int ntl_id;
  bool local_player;
''',
         r'''  int ntl_id;
  /* The tag in NTL's corner of this snake's skin block (callback.c), as an
     index into the tag sheet plus one: 0 is none, so a zeroed snake (the AI
     arena's) wears nothing. */
  int skin_tag;
  bool local_player;
'''),
    ],
    'app/src/game/tags.c': [
        (r'''  int index = (mine && tags_valid(usrs->tag_index)) ? usrs->tag_index
              : slot                               ? slot->tag
                                                   : -1;
''',
         r'''  /* Someone else's: the tag socket's when it named one, else the one in
     NTL's corner of their skin block (`skin_tag`, index + 1), as NTL does. */
  int index = (mine && tags_valid(usrs->tag_index)) ? usrs->tag_index
              : slot && tags_valid(slot->tag)      ? slot->tag
                                                   : o->skin_tag - 1;
'''),
    ],
    'app/src/network/ntl_net.c': [
        (r'''/* Long enough that a service which is simply down is not hammered, short enough
   that a player who was disconnected mid-match gets their tags back. */
#define NTL_RETRY_MS 15000
''',
         r'''/* NTL's own pace (OM, 2026-10-04: same timing as NTL): its one-second tick
   dials again whenever the socket is gone (`Zo` from `D5`). Was 15000. */
#define NTL_RETRY_MS 1000
'''),
        (r''' * and after that only `[x, y]`. `tagid` is `-1` and `tagpass` empty unless the
 * player has *claimed* a private tag — the free and bundled ones travel on the
 * team endpoint's `tg` instead, which Wyrm already sends. So this connection is
 * here to listen, and it announces mostly so that it is allowed to.
''',
         r''' * and after that only `[x, y]`. `tagid` is `-1` and `tagpass` empty unless the
 * player has *claimed* a private tag. The free and public ones travel in the
 * corner of the join's skin block (callback.c, `ntl_tag_corner`), as NTL's
 * do, and to teammates on the team endpoint's `tg`. So this connection is
 * here to listen, and it announces mostly so that it is allowed to.
'''),
    ],
}  # end NTL_SKIN_TAG_PAIRS



# Team HUD (OM, 2026-10-04): the roster and chat window own the finger that
# lands on them; the same C as Wyrm Android's mobile/mobile_controls.c.
# (android_team.c/.h carry the drawing, edited in SharedEngine in place.)
TEAM_HUD_PAIRS = {
    'app/src/mobile/mobile_controls.c': [
        (r'''  /* The interface's own buttons belong to the interface, not to steering. */
  if (event->type == SDL_EVENT_FINGER_DOWN &&
      ui_overlay_leaderboard_hit(env, x, y)) {''',
         r'''  /* The team roster and chat window own the finger that lands on them
     (scrolling, folding, the message box); every other finger keeps
     steering, so nothing is reset (OM, 2026-10-04). */
  if (android_team_hud_touch(env, (int)event->type,
                             (unsigned long long)finger, x, y))
    return true;

  /* The interface's own buttons belong to the interface, not to steering. */
  if (event->type == SDL_EVENT_FINGER_DOWN &&
      ui_overlay_leaderboard_hit(env, x, y)) {'''),
    ],
    # Stats BACK (OM, 2026-10-05): same line as Android's ui_overlay.c.
    'app/src/game/ui_overlay.c': [
        (r'''      draw_hud_paper(draw, min, max, stats_alpha);
''',
         r'''      /* BACK (OM, 2026-10-05): the plate alone fades; the rows keep
         OPACITY. */
      draw_hud_paper(draw, min, max, stats_alpha * android_team_stats_panel());
'''),
    ],
}  # end TEAM_HUD_PAIRS

def apply_run_capture(text):
    def once(old, new):
        nonlocal text
        if text.count(old) != 1:
            raise SystemExit(f"run capture: anchor not unique in tcontext.c: {old[:60]!r}")
        text = text.replace(old, new, 1)

    once('#include "tcontext.h"\n', RUN_CAPTURE_PROTOTYPES)
    # The swapchain adds TRANSFER_SRC only when the surface offers it, and is
    # built again without it if the driver still refuses: a screenshot must
    # never cost the game its swapchain.
    once('''  VkResult result = vkCreateSwapchainKHR(
      context->device,
      &(VkSwapchainCreateInfoKHR){''',
         '''  VkSwapchainCreateInfoKHR wyrm_swapchain_info = (VkSwapchainCreateInfoKHR){''')
    once('          .imageUsage = VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT,',
         '''          .imageUsage = VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT |
                        wyrm_capture_usage(context, capabilities.supportedUsageFlags),''')
    once('''          .oldSwapchain = context->old_swapchain},
      NULL, &context->swapchain);''',
         '''          .oldSwapchain = context->old_swapchain};
  VkResult result = vkCreateSwapchainKHR(context->device, &wyrm_swapchain_info,
                                         NULL, &context->swapchain);
  if (result != VK_SUCCESS &&
      (wyrm_swapchain_info.imageUsage & VK_IMAGE_USAGE_TRANSFER_SRC_BIT)) {
    wyrm_capture_refused(result);
    wyrm_swapchain_info.imageUsage = VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT;
    /* The failed call retired the old swapchain, which may not be passed
       again. */
    wyrm_swapchain_info.oldSwapchain = VK_NULL_HANDLE;
    context->swapchain = VK_NULL_HANDLE;
    result = vkCreateSwapchainKHR(context->device, &wyrm_swapchain_info, NULL,
                                  &context->swapchain);
  }''')
    # A finished copy is read once its frame's fence has signalled; checked
    # after this slot's own wait, before its reset.
    once('  vkWaitForFences(context->device, 1, &fr->wait_fence, VK_TRUE, UINT64_MAX);\n',
         '  vkWaitForFences(context->device, 1, &fr->wait_fence, VK_TRUE, UINT64_MAX);\n'
         '  wyrm_capture_harvest(context);\n')
    # The copy is recorded after the render pass, before recording ends.
    once('''  vkCmdEndRenderPass(fr->cmd);
  vkEndCommandBuffer(fr->cmd);''',
         '''  vkCmdEndRenderPass(fr->cmd);
  wyrm_capture_record(context);
  vkEndCommandBuffer(fr->cmd);''')
    once('''      fr->wait_fence);
  if (submit_result != VK_SUCCESS) {''',
         '''      fr->wait_fence);
  wyrm_capture_submitted(context, submit_result == VK_SUCCESS);
  if (submit_result != VK_SUCCESS) {''')
    once('void tcontext_destroy(tcontext* context) {\n',
         'void tcontext_destroy(tcontext* context) {\n  wyrm_capture_release(context);\n')
    return text + (ROOT / 'SourcesOriginal' / 'AppleRunCapture.inc').read_text(encoding="utf-8")


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
        # Same text as Android's redraw.c (OM, 2026-10-04, drop test): colour
        # wheel and Wyrm beads off; our own snake is drawn from the slither
        # colours the join carried.
        own = '''static uint32_t built_skin_rgba(tenv* env, snake* o, int index) {
  tuser_data* usr = env->usr;
  if (!o->cusk || index < 0 || index >= MAX_SKIN_CODE_LEN) return 0;
  if (o->id == usr->gdata.data.snake_id) return usr->usrs.skin_rgba[index];'''
        assert text.count(own) == 1
        text = text.replace(own, '''/* Colour wheel and Wyrm beads on our own snake (OM, 2026-10-04; 0 for one
 * drop-test build): 1 draws the exact colours we built, on this device only.
 * Everyone else, and the arena, get the slither colours the join carried.
 * 0 draws our snake from those slither colours too. */
#define WYRM_BUILT_BEADS_IN_ARENA 1

static uint32_t built_skin_rgba(tenv* env, snake* o, int index) {
  tuser_data* usr = env->usr;
  if (!o->cusk || index < 0 || index >= MAX_SKIN_CODE_LEN) return 0;
  if (o->id == usr->gdata.data.snake_id)
    return WYRM_BUILT_BEADS_IN_ARENA ? usr->usrs.skin_rgba[index] : 0;''')
        text = apply_air_skin_render(text)
        text = apply_wyrm_backgrounds_redraw(text)
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
        text = apply_render_gate(text)
    if relative == "app/src/game/backgrounds.h":
        text = apply_wyrm_backgrounds_table(text)
    if relative == "app/src/ui/skin_editor.c":
        text = apply_wyrm_backgrounds_skin_editor(text)
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
            # to /v1/me/stats exactly as Android's Kotlin outbox does. It also
            # carries the life's length and asks for the death-frame screenshot
            # ("Share this run", 2026-09-30; Android: recordRunFromNative(IID)V).
             # Where the run ended first: a red dot on the minimap during the
             # next run (ui_overlay.c draw_last_death, OM 2026-10-02; Android
             # calls the same wyrm_last_death_set). Real arenas only.
             'record_finished_run': '''extern void WyrmIOSRecordFinishedRun(int score, int kills, double play_time);
  extern void wyrm_last_death_set(float x, float y);
  if (!env->usr->gdata.ai_mode)
    wyrm_last_death_set(env->usr->gdata.data.view_xx,
                        env->usr->gdata.data.view_yy);
  WyrmIOSRecordFinishedRun(env->usr->usrs.score, env->usr->usrs.kills,
                           env->usr->usrs.play_time);''',
             'android_home_set_screen': '(void)screen;',
             'android_home_set_arena_port_available': '(void)available;',
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
        text = text.replace(timeout, '''          {
            extern void WyrmIOSArenaNoteTimeout(void);
            WyrmIOSArenaNoteTimeout();
          }
          game_fail_connection(gdata, "configuration timeout");''')
        failed = '''          /* Report this attempt's refusal and return to the lobby. A new
             endpoint may be chosen there only by the player; one Play must
             not silently create another arena connection. */
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
        # Arena drop, the second close path: no death is pending here (the
        # branch above took that case), so the same test minus the watch.
        # Read-only; the death fade that follows is unchanged. HomeMailbox.inc
        # publishes once per connection, so a drop seen by both paths is one.
        onclose = '''             after the death wait. Instant lobby here was the mid-match eject. */
          android_home_notify_death(env);'''
        assert text.count(onclose) == 1
        text = text.replace(onclose, '''             after the death wait. Instant lobby here was the mid-match eject. */
          if (!gdata->closed_by_us) {
            extern void WyrmIOSArenaDropped(tenv* env);
            WyrmIOSArenaDropped(env);
          }
          android_home_notify_death(env);''')
    if relative == "app/src/network/server.c":
        # Arena drops: every dial stamps a ring, so a drop report can say how
        # many connects the last minute held (the arena's IP penalty). The
        # dial itself is unchanged.
        dialled = '  gdata->last_connect_ms = gdata->last_packet_ms;\n'
        assert text.count(dialled) == 1
        text = text.replace(dialled, dialled + '''  {
    extern void WyrmIOSArenaConnectStamp(void);
    WyrmIOSArenaConnectStamp();
  }
''')
    if relative == "app/src/network/callback.c":
        # Arena drop fix (OM, 2026-09-29), the same C as Wyrm Android: the
        # custom skin block was unbounded (a 246-run, 500-byte block made the
        # arena close before 'a'). Official colours only, one repeat, at most
        # 47 runs; the tail only for the web persona and only with runs; our
        # own snake keeps its whole design locally.
        old_encoder_start = text.index('uint8_t* get_skin_compressed(tuser_data* usr) {')
        old_encoder_end = text.index('  return reduced;\n}\n', old_encoder_start) + len('  return reduced;\n}\n')
        assert 'A run byte cannot spell 256' in text[old_encoder_start:old_encoder_end]
        text = text[:old_encoder_start] + NEW_SKIN_ENCODER + text[old_encoder_end:]
        skin_alloc = """    if (usrs->custom_skin) {
      skin_compressed = get_skin_compressed(usr);
      skin_compressed_len = tdarray_length(skin_compressed);
      ba = malloc(8 + 20 + nick_len + 8 + skin_compressed_len);
    } else {
      ba = malloc(8 + 20 + nick_len);
    }
"""
        assert text.count(skin_alloc) == 1
        text = text.replace(skin_alloc, """    /* The skin tail is the web client's format. The AIR client sends typed
       `custom_skin2` blocks instead, which Wyrm does not encode, so an AIR
       join goes out as a preset one. A tail with no runs is not sent either:
       receivers need at least one pair. */
    bool web_persona = persona == arena_persona_get(ARENA_PERSONA_WEB);
    if (usrs->custom_skin && web_persona) {
      skin_compressed = get_skin_compressed(usr);
      skin_compressed_len = tdarray_length(skin_compressed);
      if (!skin_compressed_len) {
        tdarray_destroy(skin_compressed);
        skin_compressed = NULL;
      }
    }
    ba = malloc(8 + 20 + nick_len + (skin_compressed ? 8 + skin_compressed_len : 0));
""")
        skin_tail = '    if (usrs->custom_skin) {\n      ba[m++] = 255;\n'
        assert text.count(skin_tail) == 1
        text = text.replace(skin_tail, '    if (skin_compressed) {\n      ba[m++] = 255;\n')
        own_look = '      o.cusk = skl != 0;\n'
        assert text.count(own_look) == 1
        text = text.replace(own_look, own_look + """      /* Our own snake keeps the whole design we chose. The join carries at
         most one bounded repeat of it, and `cusk_data` above holds the arena's
         echo of that; drawn from the echo, our snake would show the trimmed
         wire copy instead of the player's own look. */
      if (o.local_player && usrs->custom_skin) {
        o.cusk_len = 0;
        for (int k = 0; k < MAX_SKIN_CODE_LEN && usrs->skin_code[k]; k++) {
          int cg = get_cg_id(gdata, usrs->skin_code[k]);
          if (cg >= 0) o.cusk_data[o.cusk_len++] = (uint8_t)cg;
        }
        o.cusk = o.cusk_len > 0;
      }
""")
        # Arena drops, the fast kind: the arena ends the snake with a 'v'
        # 0.3-1 s after it spawned (OM, 2026-09-29). Reported first, read-only;
        # the death handling that follows is unchanged.
        death_packet = '''  } else if (cmd == 'v') {
    if (a[m] == 2) {'''
        assert text.count(death_packet) == 1
        text = text.replace(death_packet, '''  } else if (cmd == 'v') {
    {
      extern void WyrmIOSArenaFastDeath(tenv* env, int death_code);
      WyrmIOSArenaFastDeath(env, a[m]);
    }
    if (a[m] == 2) {''')
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
      /* Kept for an arena-drop report (HomeMailbox.inc). */
      extern void WyrmIOSArenaCloseFrame(const uint8_t* data, size_t length);
      WyrmIOSArenaCloseFrame((const uint8_t*)ctl->data.buf, ctl->data.len);
    }
  } else if (ev == MG_EV_ERROR) {
    {
      extern void WyrmIOSArenaNoteError(const char* text);
      WyrmIOSArenaNoteError((const char*)ev_data);
    }''')
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
        text = text.replace(joined, '''    SDL_Log("Wyrm arena: join fields accessory=%u custom_skin=%d skin_runs=%d skin_bytes=%d nickname_bytes=%d packet_bytes=%d",
            (unsigned)usrs->accessory, usrs->custom_skin ? 1 : 0,
            skin_compressed_len / 2, skin_compressed_len ? 8 + skin_compressed_len : 0,
            nick_len, m);
    {
      extern void WyrmIOSArenaJoinFacts(int packet_bytes, int skin_bytes, int skin_runs,
                                        int nick_bytes, int custom_skin);
      WyrmIOSArenaJoinFacts(m, skin_compressed_len ? 8 + skin_compressed_len : 0,
                            skin_compressed_len / 2, nick_len, usrs->custom_skin ? 1 : 0);
    }
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
    /* Turned away before a snake existed (and not by us): a drop report of
       its own (HomeMailbox.inc). Refusal handling is unchanged; every
       post-spawn report needs join_spawned, so the two never fire together. */
    if (c->is_websocket && !gdata->join_spawned && !gdata->ai_mode &&
        !gdata->closed_by_us && !gdata->leaving && !gdata->restart_req) {
      extern void WyrmIOSArenaPrespawnClosed(tenv* env, const char* phase);
      WyrmIOSArenaPrespawnClosed(env, phase);
    }
''' + closing)
        close_block = '''    if (gdata->arena_ready && gdata->curr_screen == PLAYING &&
        !gdata->leaving && !gdata->restart_req) {
      android_home_notify_death(env);
      game_clear_world(gdata);
      gdata->arena_ready = false;
    }
'''
        assert text.count(close_block) == 1
        text = text.replace(close_block, '''    /* Arena drop: judged before the death watch starts (once it has, a death
       is always pending) and before a short-life refusal clears join_spawned,
       because a silent close right after spawning is the drop players see
       most. Read-only; the fade and the refusal below are unchanged. */
    bool wyrm_arena_drop =
        gdata->join_spawned &&
        !gdata->closed_by_us && !gdata->leaving && !gdata->restart_req &&
        !android_home_death_pending();
    if (wyrm_arena_drop) {
      extern void WyrmIOSArenaDropped(tenv* env);
      WyrmIOSArenaDropped(env);
    }
    bool refused_short_life =
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
    if relative == "app/src/ui/lobby.c":
        # A blank name is allowed: the arena shows no name (OM, 2026-09-30).
        gate = 'bool can_play = usrs->nickname[0] && server_address_is_valid(usrs->ipv4);'
        assert text.count(gate) == 1
        text = text.replace(gate, 'bool can_play = server_address_is_valid(usrs->ipv4);')
    if relative == "app/src/network/arena_persona.c":
        # Web persona only (OM, 2026-10-04); was a clamp from AIR to WEB.
        assert 'ARENA_PERSONA_AIR' in text
        text = WEB_PERSONA_C
    if relative == "app/src/network/arena_persona.h":
        assert 'ARENA_PERSONA_AIR' in text
        text = WEB_PERSONA_H
    if relative == "app/src/network/callback.c":
        for old, new in WEB_ONLY_PAIRS:
            assert text.count(old) == 1, old[:60]
            text = text.replace(old, new)
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
    if relative == "app/src/ui/viewport.c":
        # Same guard as Android's viewport.c (crash report 2026-10-02): a
        # 0 x 0 surface makes VMA refuse the image and the view crashes.
        resize = '  tcontext* ctx = env->ctx;\n  renderer_resize(usr->r, ctx, ctx->size);\n'
        assert text.count(resize) == 1
        text = text.replace(resize, '  tcontext* ctx = env->ctx;\n'
                            '  if (ctx->size[0] <= 0 || ctx->size[1] <= 0) return;\n'
                            '  renderer_resize(usr->r, ctx, ctx->size);\n')
    if relative == "thermite/src/graphics/tcontext.c":
        text = '#include "WyrmOriginalAdapter.h"\n' + text
        text = text.replace('vkCreateInstance(', 'WyrmIOSCreateInstance(')
        text = text.replace('vkCreateDevice(', 'WyrmIOSCreateDevice(')
        # Same text as Android's tcontext.c (crash reports 2026-10-03, build
        # 91: vkCreateSwapchainKHR -4 at launch, then the recovery resize
        # destroyed the freed views again -> SIGSEGV in vkDestroyImageView).
        for old, new in SWAPCHAIN_REBUILD_PAIRS:
            assert text.count(old) == 1, old[:60]
            text = text.replace(old, new)
        text = apply_run_capture(text)
    for old, new in TEAM_HUD_PAIRS.get(relative, []):
        assert text.count(old) == 1, (relative, old[:60])
        text = text.replace(old, new)
    for old, new in NTL_SKIN_TAG_PAIRS.get(relative, []):
        assert text.count(old) == 1, (relative, old[:60])
        text = text.replace(old, new)
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
  /* An image arrow keeps its own colours: only its fade applies, not the
     controls opacity, which washed it into the arena behind it. */
  if (WyrmIOSDrawArrowImage(dl, ax, ay, dx, dy, length,
                            env->usr->mobile_controls.arrow_opacity / 0.85f))
    return;
  float wyrm_brightness = WyrmIOSArrowBrightness();
  mobile_arrow_shape shape = arrow_shape(env->usr->usrs.arrow_style);"""),
    ("""  ImU32 fill =
      color_u32(arrow->color[0], arrow->color[1], arrow->color[2], alpha);""",
     """  ImU32 fill = color_u32(arrow->color[0] * wyrm_brightness,
                         arrow->color[1] * wyrm_brightness,
                         arrow->color[2] * wyrm_brightness, alpha);"""),
])
print("Arrow skins: renderer atlas and draw_arrow hook applied")

# --- Wyrm looks: hair, ears, glasses (SourcesOriginal/AppleWyrmLook.c) --------
# The player's own snake only, drawn right after slither's own accessory; the
# same call Wyrm Android makes into platform/android_look.c.
_arrow_patch("app/src/rendering/renderer.c", [
    ("""    WyrmIOSArrowSkinsCreate(r, ctx);
  }
""", """    WyrmIOSArrowSkinsCreate(r, ctx);
    extern void WyrmIOSLookCreate(renderer* r, tcontext* ctx);
    WyrmIOSLookCreate(r, ctx);
  }
"""),
    ("""    WyrmIOSArrowSkinsDestroy(ctx);
  }
""", """    WyrmIOSArrowSkinsDestroy(ctx);
    extern void WyrmIOSLookDestroy(tcontext* ctx);
    WyrmIOSLookDestroy(ctx);
  }
"""),
])
_arrow_patch("app/src/game/redraw.c", [
    ("""                    {acx - m, acy - m, m * 2, fang}, acc->uv, {1, 1, 1, ea}});
          }
""", """                    {acx - m, acy - m, m * 2, fang}, acc->uv, {1, 1, 1, ea}});
          }
          if (o->id == gdata->data.snake_id) {
            extern void wyrm_look_draw(tenv* env, float hx, float hy, float fang,
                                       float lsz, float alpha, float mww2,
                                       float mhh2);
            wyrm_look_draw(env, hx, hy, fang, lsz, ea, mww2, mhh2);
          }
"""),
])
print("Wyrm looks: renderer atlas and redraw hook applied")


# Bare editor (OM, 2026-10-01; Android engine has the same change): the
# background-size editor shows only the AI arena's real minimap and
# leaderboard, no controls, buttons, stats, team or chat, with assist off while
# it is open. WyrmIOSSetEditorBare (HomeMailbox.inc) switches it.
BARE_EDITOR_PAIRS = {
"app/src/game/ai_mode.h": [
("bool ai_mode_is_editor(void);",
 """bool ai_mode_is_editor(void);
/* Background-size editor: only the real minimap and leaderboard over the AI
   arena, assist off while it is open (OM, 2026-10-01). */
void ai_mode_set_editor_bare(bool bare);
bool ai_mode_editor_bare(void);"""),
],
"app/src/game/ai_mode.c": [
("""void ai_mode_start_editor(tenv* e, const char* nick) {
  editor_session = true;
  ai_mode_start(e, nick);
}
bool ai_mode_is_editor(void) { return editor_session; }""",
"""/* The background-size editor (OM, 2026-10-01): no controls, no buttons, no
   stats; assist off so the floor shows, and back as it was on close. */
static bool editor_bare;
static bool bare_assist_saved;
static bool bare_assist_was;
void ai_mode_set_editor_bare(bool bare) { editor_bare = bare; }
bool ai_mode_editor_bare(void) { return editor_session && editor_bare; }

void ai_mode_start_editor(tenv* e, const char* nick) {
  editor_session = true;
  if (editor_bare && !bare_assist_saved) {
    bare_assist_was = e->usr->usrs.hotkeys[HOTKEY_ASSIST].active;
    bare_assist_saved = true;
  }
  if (editor_bare) e->usr->usrs.hotkeys[HOTKEY_ASSIST].active = false;
  ai_mode_start(e, nick);
}
bool ai_mode_is_editor(void) { return editor_session; }"""),
("""void ai_mode_finish_editor(tenv* e) {
  editor_session = false;""",
"""void ai_mode_finish_editor(tenv* e) {
  if (bare_assist_saved) {
    e->usr->usrs.hotkeys[HOTKEY_ASSIST].active = bare_assist_was;
    bare_assist_saved = false;
  }
  editor_bare = false;
  editor_session = false;"""),
("""  mobile_controls_draw_gameplay(e);
  draw_notice(e);""",
"""  if (!ai_mode_editor_bare()) mobile_controls_draw_gameplay(e);
  draw_notice(e);"""),
],
"app/src/game/ui_overlay.c": [
('#include "ui_overlay.h"\n', '#include "ui_overlay.h"\n#include "ai_mode.h"\n'),
("""    /* ---- what you are doing, directly under the leaderboard ---- */
    {""",
"""    /* ---- what you are doing, directly under the leaderboard ---- */
    /* Not in the background-size editor: only the map and the board there. */
    if (!ai_mode_editor_bare()) {"""),
("""    android_team_draw_roster_centered(env, usrs->hud_team_x * ctx->size[0],
                                      usrs->hud_team_y * ctx->size[1]);""",
"""    if (!ai_mode_editor_bare())
      android_team_draw_roster_centered(env, usrs->hud_team_x * ctx->size[0],
                                        usrs->hud_team_y * ctx->size[1]);"""),
],
}


# Phase 3 G (OM, 2026-10-01; Wyrm Android's server.c has the same text): the
# per-frame 5 ms network wait runs on the main thread here, inside SDL's
# display-link callback (8.3 ms per frame at 120 Hz). The arena socket is plain
# ws://, so once the WebSocket is open the poll waits 0 ms; while connecting it
# keeps 5 ms. No packet, timing or keepalive change. Logs a 10 s measurement.
NET_POLL_OLD = "void server_poll(tenv* env) {\n  tuser_data* usr = env->usr;\n  game_data* gdata = &usr->gdata;\n\n  /* Vlither blocks 5ms here on Android and 0ms elsewhere. A non-blocking poll\n     is fine over plaintext, where a frame's worth of bytes is already sitting\n     in the socket; a TLS record has to be assembled before there is anything to\n     hand up, and starving that is how a working connection reads as a dead\n     one. */\n#ifdef WYRM_MOBILE\n  mg_mgr_poll(&gdata->network_manager, 5);\n#else\n  mg_mgr_poll(&gdata->network_manager, 0);\n#endif\n}"
NET_POLL_NEW = 'void server_poll(tenv* env) {\n  tuser_data* usr = env->usr;\n  game_data* gdata = &usr->gdata;\n\n#ifdef WYRM_MOBILE\n  /* Phase 3 G (OM, 2026-10-01). Vlither blocked 5 ms here on every frame; its\n     reason was TLS, but the arena socket is plain `ws://` now (see\n     server_connect), so there is no record to assemble. While the socket is\n     still connecting, upgrading or answering the challenge (until the arena\'s\n     \'a\') the 5 ms stays exactly as it was, so entry is untouched; once \'a\'\n     has come the poll only drains what is already there (0 ms), so a\n     frame that finds the socket empty no longer loses up to 5 ms, and ping\n     (counted in frame time) stops carrying that wait. No packet, timing or\n     keepalive changed. Rollback: set WYRM_NET_POLL_OPEN_MS to 5. */\n#ifndef WYRM_NET_POLL_OPEN_MS\n#define WYRM_NET_POLL_OPEN_MS 0\n#endif\n  struct mg_connection* arena = gdata->connection;\n  int wait_ms = (arena && arena->is_websocket && gdata->arena_ready &&\n                 !gdata->closed)\n                    ? WYRM_NET_POLL_OPEN_MS : 5;\n  Uint64 started = SDL_GetTicksNS();\n  mg_mgr_poll(&gdata->network_manager, wait_ms);\n  Uint64 ended = SDL_GetTicksNS();\n\n  /* Measurement for OM\'s before/after check: every 10 s while a WebSocket is\n     open, how long the poll took and how far apart the frames were. */\n  static Uint64 window_start, last_call, poll_sum, poll_max, gap_sum, gap_max;\n  static unsigned frames;\n  if (arena && arena->is_websocket) {\n    if (!window_start) window_start = started;\n    Uint64 took = ended - started;\n    poll_sum += took;\n    if (took > poll_max) poll_max = took;\n    if (last_call) {\n      Uint64 gap = started - last_call;\n      gap_sum += gap;\n      if (gap > gap_max) gap_max = gap;\n    }\n    frames++;\n    if (ended - window_start >= 10000000000ULL && frames > 1) {\n      SDL_Log("Wyrm net poll: wait %d ms, poll avg %.2f ms max %.2f ms, "\n              "frame avg %.2f ms max %.2f ms over %u frames",\n              wait_ms, poll_sum / 1e6 / frames, poll_max / 1e6,\n              gap_sum / 1e6 / (frames - 1), gap_max / 1e6, frames);\n      window_start = ended;\n      poll_sum = poll_max = gap_sum = gap_max = 0;\n      frames = 0;\n    }\n    last_call = started;\n  } else {\n    window_start = last_call = 0;\n    poll_sum = poll_max = gap_sum = gap_max = 0;\n    frames = 0;\n  }\n#else\n  mg_mgr_poll(&gdata->network_manager, 0);\n#endif\n}'
_target = OUTPUT / "app/src/network/server.c"
_text = _target.read_text(encoding="utf-8")
_nl = "\r\n" if "\r\n" in _text else "\n"
_old, _new = NET_POLL_OLD.replace("\n", _nl), NET_POLL_NEW.replace("\n", _nl)
if _text.count(_old) != 1:
    raise SystemExit("net poll: server_poll anchor missing in app/src/network/server.c")
_target.write_text(_text.replace(_old, _new, 1), encoding="utf-8")
print("Net poll: 0 ms once the arena WebSocket is open")

for _relative, _pairs in BARE_EDITOR_PAIRS.items():
    _target = OUTPUT / _relative
    _text = _target.read_text(encoding="utf-8")
    _nl = "\r\n" if "\r\n" in _text else "\n"
    for _old, _new in _pairs:
        _old, _new = _old.replace("\n", _nl), _new.replace("\n", _nl)
        if _text.count(_old) != 1:
            raise SystemExit(f"bare editor: anchor missing in {_relative}: {_old[:60]!r}")
        _text = _text.replace(_old, _new, 1)
    _target.write_text(_text, encoding="utf-8")
print("Bare background-size editor applied")

# Phase 3 H (OM, 2026-10-01; Wyrm Android has the same C): the HUD
# performance chip under the stats. HomeMailbox.inc holds the text
# (WyrmIOSSetPerformanceChip from WyrmPerformance.swift); the engine only draws.
PERFORMANCE_CHIP_PAIRS = {
"app/src/platform/android_home.h": [('bool android_home_death_pending(void);', 'bool android_home_death_pending(void);\n/* Phase 3 H: the HUD performance chip, "" for none (set by the app). */\nvoid android_home_set_performance_chip(const char* text);\nconst char* android_home_performance_chip(void);')],
"app/src/game/ui_overlay.c": [('#include "../platform/android_voice.h"\n', '#include "../platform/android_voice.h"\n#include "../platform/android_home.h"\n'), ('        draw_stat_row(env, draw, max.x - pad, y, labels[i], values[i], 0.88f);\n        y += row_height;\n      }\n    }', '        draw_stat_row(env, draw, max.x - pad, y, labels[i], values[i], 0.88f);\n        y += row_height;\n      }\n\n      /* Phase 3 H (OM, 2026-10-01): when Auto has stepped the frame rate down\n         (heat, Battery Saver / Low Power Mode), a small chip under the stats\n         says why ms or smoothness changed. The app sets the text; nothing\n         here touches input or gameplay. */\n      const char* chip = android_home_performance_chip();\n      if (chip && chip[0] && stats_alpha > 0.01f) {\n        ImVec2 chip_text = measure_scaled(stats_label_font, chip, stats_scale);\n        float chip_pad = 8.0f * stats_scale;\n        float chip_w = chip_text.x + chip_pad * 2;\n        float chip_h = chip_text.y + chip_pad;\n        float chip_y = max.y + 6.0f * stats_scale;\n        if (chip_y + chip_h > ctx->size[1] - edge)\n          chip_y = min.y - 6.0f * stats_scale - chip_h;\n        ImVec2 chip_min = {max.x - chip_w, chip_y};\n        ImVec2 chip_max = {max.x, chip_y + chip_h};\n        draw_hud_paper(draw, chip_min, chip_max, stats_alpha);\n        ImDrawList_AddText_FontPtr(\n            draw, stats_label_font, stats_label_font->LegacySize * stats_scale,\n            (ImVec2){chip_min.x + chip_pad, chip_min.y + chip_pad * 0.5f},\n            arena_theme_colour(ARENA_THEME_INK, 0.86f * stats_alpha), chip,\n            NULL, 0, NULL);\n      }\n    }')],
}
for _relative, _pairs in PERFORMANCE_CHIP_PAIRS.items():
    _target = OUTPUT / _relative
    _text = _target.read_text(encoding="utf-8")
    _nl = "\r\n" if "\r\n" in _text else "\n"
    for _old, _new in _pairs:
        _old, _new = _old.replace("\n", _nl), _new.replace("\n", _nl)
        if _text.count(_old) != 1:
            raise SystemExit(f"performance chip: anchor missing in {_relative}: {_old[:60]!r}")
        _text = _text.replace(_old, _new, 1)
    _target.write_text(_text, encoding="utf-8")
print("Performance chip applied")


# The joystick knob follows the snake (OM, 2026-10-01; Wyrm Android's
# mobile/mobile_controls.c has the same C). After the main pass, so the
# platform macro is already WYRM_MOBILE here.
JOYSTICK_KNOB_PAIRS = [
    ("""#ifdef VLITHER_ANDROID
static void update_joystick(tenv* env, float x, float y) {""",
     """/*
 * The joystick knob follows the snake (OM, 2026-10-01).
 *
 * The own snake's heading, as the head is drawn (`ehang`, the same smoothed
 * angle the head bead turns with). A dynamic joystick starts with its knob on
 * that side instead of in the centre, and a fixed one rests there between
 * touches, so the stick always shows where the snake is going. Steering is
 * unchanged: the first frame of a new touch aims exactly where the snake
 * already goes, and moving the finger steers from there.
 */
static bool joystick_heading(tenv* env, float* hx, float* hy) {
  game_data* gdata = &env->usr->gdata;
  snake* own = get_snake(gdata, gdata->data.snake_id);
  if (!own || own->dead) return false;
  *hx = cosf(own->ehang);
  *hy = sinf(own->ehang);
  return true;
}

#ifdef VLITHER_ANDROID
static void update_joystick(tenv* env, float x, float y) {"""),
    ("""    } else if (cfg->joystick_mode == MOBILE_JOYSTICK_DYNAMIC &&
               !state->joystick_down && in_joystick_half) {
      state->joystick_down = true;
      state->joystick_finger = finger;
      state->joystick_origin[0] = x;
      state->joystick_origin[1] = y;
      update_joystick(env, x, y);
      return true;
    }""",
     """    } else if (cfg->joystick_mode == MOBILE_JOYSTICK_DYNAMIC &&
               !state->joystick_down && in_joystick_half) {
      state->joystick_down = true;
      state->joystick_finger = finger;
      state->joystick_origin[0] = x;
      state->joystick_origin[1] = y;
      /* The base is placed so the finger holds the knob on the snake's side:
         the stick starts where the snake is going, not in the centre. */
      float hx, hy;
      if (joystick_heading(env, &hx, &hy)) {
        float reach = 92.0f * control_scale(env) * cfg->joystick_size;
        state->joystick_origin[0] = x - hx * reach;
        state->joystick_origin[1] = y - hy * reach;
      }
      update_joystick(env, x, y);
      return true;
    }"""),
    ("""  float kx = cx + state->joystick_axis[0] * radius * 0.58f;
  float ky = cy + state->joystick_axis[1] * radius * 0.58f;
  if (editor) {""",
     """  float ax = state->joystick_axis[0];
  float ay = state->joystick_axis[1];
  /* At rest (or held in the dead zone) the knob shows where the snake goes. */
  float hx, hy;
  if (!editor && (!active || (fabsf(ax) < 0.08f && fabsf(ay) < 0.08f)) &&
      joystick_heading(env, &hx, &hy)) {
    ax = hx;
    ay = hy;
  }
  float kx = cx + ax * radius * 0.58f;
  float ky = cy + ay * radius * 0.58f;
  if (editor) {"""),
]

_arrow_patch("app/src/mobile/mobile_controls.c",
             [(old.replace("VLITHER_ANDROID", "WYRM_MOBILE"), new.replace("VLITHER_ANDROID", "WYRM_MOBILE"))
              for old, new in JOYSTICK_KNOB_PAIRS])
print("Joystick knob follows the snake")


# Assist laser in joystick mode (OM, 2026-10-01; Wyrm Android's ui_overlay.c
# and android_home.c/.h have the same C). The store is in HomeMailbox.inc.
JOYSTICK_LASER_HEADER = '/* Assist laser in joystick mode: on/off and length (share of the short\n   side, 0.1-1.0). Set by the app (Settings > Modes > Assist). */\nvoid android_home_set_joystick_laser(bool on, float length);\nbool android_home_joystick_laser_on(void);\nfloat android_home_joystick_laser_length(void);\n'
JOYSTICK_LASER_DRAW = ('            usrs->laser_thickness);\n      }\n', "            usrs->laser_thickness);\n      }\n\n      /* Assist laser in joystick mode (OM, 2026-10-01/02). With assist on and\n         a joystick (not the arrow, which has its own line), a line from the\n         front of the head where the snake is going, like the collision dot:\n         the drawn head's own angle (`ehang`), never the stick. Its length is a\n         share of the screen's short side, set in Settings > Modes > Assist;\n         colour and thickness are the laser's. Draw-only: no input, no packet. */\n      if (usrs->hotkeys[HOTKEY_ASSIST].active &&\n          usrs->mobile_controls.joystick_mode != MOBILE_STEERING_ARROW &&\n          android_home_joystick_laser_on() && a > 0.01f) {\n        float lx = cosf(me->ehang);\n        float ly = sinf(me->ehang);\n        float shortest = ctx->size[0] < ctx->size[1] ? (float)ctx->size[0]\n                                                     : (float)ctx->size[1];\n        float reach = android_home_joystick_laser_length() * shortest;\n        /* The head bead's half size (14.5), as the collision dot uses it. */\n        float front = 14.5f * me->sc * gdata->data.gsc;\n        ImVec2 from = {mww2 + (hx - gdata->data.view_xx) * gdata->data.gsc + lx * front,\n                       mhh2 + (hy - gdata->data.view_yy) * gdata->data.gsc + ly * front};\n        ImDrawList_AddLine(\n            igGetWindowDrawList(), from,\n            (ImVec2){from.x + lx * reach, from.y + ly * reach},\n            igColorConvertFloat4ToU32(\n                (ImVec4){usrs->laser_color[0], usrs->laser_color[1],\n                         usrs->laser_color[2], usrs->laser_color[3] * a}),\n            usrs->laser_thickness);\n      }\n")
_arrow_patch("app/src/platform/android_home.h", [
    ("const char* android_home_performance_chip(void);\n",
     "const char* android_home_performance_chip(void);\n" + JOYSTICK_LASER_HEADER),
])
_arrow_patch("app/src/game/ui_overlay.c", [JOYSTICK_LASER_DRAW])
print("Joystick assist laser applied")


# Portrait play (OM, 2026-10-01): controls and on-screen buttons are sized
# from the screen's short side, which is the height when sideways (so nothing
# changes there) and the width when upright (where the height made them huge).
# Shared by Wyrm Android (patched in place) and Wyrm iOS (prepare script).
CONTROL_SCALE_PAIR = ("""static float control_scale(tenv* env) {
  return clampf(env->wnd->size[1] / 720.0f, 1.0f, 1.55f);
}""", """static float control_scale(tenv* env) {
  /* The short side: the height sideways, the width upright (portrait play). */
  int short_side = env->wnd->size[0] < env->wnd->size[1] ? env->wnd->size[0]
                                                         : env->wnd->size[1];
  return clampf(short_side / 720.0f, 1.0f, 1.55f);
}""")

BUTTON_SCALE_PAIR = ("""static float button_scale(tenv* env) {
  return clampf_local(env->wnd->size[1] / 720.0f, 0.82f, 1.45f);
}""", """static float button_scale(tenv* env) {
  /* The short side: the height sideways, the width upright (portrait play). */
  int short_side = env->wnd->size[0] < env->wnd->size[1] ? env->wnd->size[0]
                                                         : env->wnd->size[1];
  return clampf_local(short_side / 720.0f, 0.82f, 1.45f);
}""")

_arrow_patch("app/src/mobile/mobile_controls.c", [CONTROL_SCALE_PAIR])
_arrow_patch("app/src/mobile/mobile_hotkeys.c", [BUTTON_SCALE_PAIR])
print("Portrait play: controls sized from the short side")


# Portrait play has no handedness (OM, 2026-10-02; Wyrm Android's
# mobile/mobile_controls.c has the same C): upright, the first finger anywhere
# steers and a second finger anywhere boosts. Sideways unchanged.
UPRIGHT_HANDS_PAIR = ('    bool joystick_left = cfg->handedness == MOBILE_LEFT_HANDED;\n    bool in_joystick_half = joystick_left ? x < mid : x >= mid;\n', '    bool joystick_left = cfg->handedness == MOBILE_LEFT_HANDED;\n    bool in_joystick_half = joystick_left ? x < mid : x >= mid;\n    /* Upright there is no left or right hand (OM, 2026-10-02): the first free\n       finger anywhere starts the dynamic joystick, and once a joystick is\n       held (or it is a fixed one) any other finger is touch-zone boost, the\n       way Arrow steering already works. Fixed controls keep their drawn hit\n       circles above. Sideways is unchanged. Only which finger starts which\n       control changes; nothing is sent differently. */\n    if (env->wnd->size[1] > env->wnd->size[0])\n      in_joystick_half = cfg->joystick_mode == MOBILE_JOYSTICK_DYNAMIC &&\n                         !state->joystick_down;\n')
_arrow_patch("app/src/mobile/mobile_controls.c", [UPRIGHT_HANDS_PAIR])
print("Portrait play: no left or right hand")

# Upright play steers with the arrow only, and the previous run's death spot is
# a red dot on the arena minimap during the next run (OM, 2026-10-02). The same
# C is in Wyrm Android (mobile_controls.c/.h, redraw.c, ui_overlay.c).
STEERING_DEF_PAIR = ('  return clampf(short_side / 720.0f, 1.0f, 1.55f);\n}\n', '  return clampf(short_side / 720.0f, 1.0f, 1.55f);\n}\n\n/* Upright play steers with the arrow only (OM, 2026-10-02): both joystick\n   modes are off while the phone is held upright, whatever is chosen for\n   sideways play (that stored choice is kept). Every reader of the steering\n   mode goes through here; nothing is sent differently. */\nint mobile_controls_steering_mode(tenv* env) {\n  if (env->wnd->size[1] > env->wnd->size[0]) return MOBILE_STEERING_ARROW;\n  return env->usr->usrs.mobile_controls.joystick_mode;\n}\n')
STEERING_DECL_PAIR = ('bool mobile_controls_boost_down(tenv* env);\n', 'bool mobile_controls_boost_down(tenv* env);\n/* The steering actually in use: always the arrow upright (portrait play). */\nint mobile_controls_steering_mode(tenv* env);\n')
REDRAW_PROTO_PAIR = ('void redraw(tenv* env) {\n', '/* mobile/mobile_controls.c: the arrow upright, the chosen steering sideways. */\nint mobile_controls_steering_mode(tenv* env);\n\nvoid redraw(tenv* env) {\n')
REDRAW_MODE_PAIR = ('usrs->mobile_controls.joystick_mode != MOBILE_STEERING_ARROW) {', 'mobile_controls_steering_mode(env) != MOBILE_STEERING_ARROW) {')
OVERLAY_MODE_PAIR = ('usrs->mobile_controls.joystick_mode != MOBILE_STEERING_ARROW &&', 'mobile_controls_steering_mode(env) != MOBILE_STEERING_ARROW &&')
LAST_DEATH_DEF_PAIR = ('static ImVec2 hud_top_left(tenv* env, float nx, float ny, float width,\n', "/* Where the previous run ended (OM, 2026-10-02): a red dot on the arena's\n   minimap during the next run, so you can see where you went down last time.\n   Set by android_home.c's record_finished_run (real arenas only), kept in\n   memory until the next run ends. Same frame as your own white dot (mm.slang:\n   (pos - grd) / flux_grd, at 0.9 of the radius). Draw-only. */\nstatic bool last_death_valid = false;\nstatic float last_death_x = 0.0f;\nstatic float last_death_y = 0.0f;\n\nvoid wyrm_last_death_set(float x, float y) {\n  if (!isfinite(x) || !isfinite(y) || (x == 0.0f && y == 0.0f)) return;\n  last_death_x = x;\n  last_death_y = y;\n  last_death_valid = true;\n}\n\nstatic void draw_last_death(tenv* env, float left, float top, float diameter) {\n  if (!last_death_valid || diameter <= 0.0f) return;\n  game_data* game = &env->usr->gdata;\n  if (game->ai_mode || ai_mode_editor_bare()) return;\n  float world_radius = game->data.flux_grd;\n  if (world_radius <= 1.0f) return;\n  float nx = (last_death_x - game->data.grd) / world_radius;\n  float ny = (last_death_y - game->data.grd) / world_radius;\n  float reach = sqrtf(nx * nx + ny * ny);\n  if (reach > 1.0f) {\n    nx /= reach;\n    ny /= reach;\n  }\n  float half = diameter * 0.5f;\n  ImVec2 point = {left + half + nx * half * 0.9f, top + half + ny * half * 0.9f};\n  float radius = diameter * 0.024f;\n  if (radius < 3.5f) radius = 3.5f;\n  if (radius > 6.5f) radius = 6.5f;\n  ImDrawList* draw = igGetForegroundDrawList_ViewportPtr(NULL);\n  /* A dark ring so it survives a pale patch of map, then Wyrm's death red\n     (the app's Blood, #FF4D4D), never the white of you or a teammate's green. */\n  ImDrawList_AddCircleFilled(draw, point, radius + 2.0f,\n                             igColorConvertFloat4ToU32((ImVec4){0, 0, 0, 0.70f}), 20);\n  ImDrawList_AddCircleFilled(draw, point, radius,\n                             igColorConvertFloat4ToU32((ImVec4){1.0f, 0.302f, 0.302f, 1.0f}), 20);\n}\n\nstatic ImVec2 hud_top_left(tenv* env, float nx, float ny, float width,\n")
LAST_DEATH_DRAW_PAIR = ('    android_team_draw_minimap(env, minimap_left, minimap_top, minimap_diameter);\n', '    android_team_draw_minimap(env, minimap_left, minimap_top, minimap_diameter);\n    draw_last_death(env, minimap_left, minimap_top, minimap_diameter);\n')
UNUSED_CFG_PAIRS = [('  {\n    mobile_control_settings* cfg = &env->usr->usrs.mobile_controls;\n    mobile_arrow_settings* arrow = &env->usr->usrs.arrow_controls;\n', '  {\n    mobile_arrow_settings* arrow = &env->usr->usrs.arrow_controls;\n'), ('                           float* dy, float* length, float* width) {\n  mobile_control_settings* cfg = &env->usr->usrs.mobile_controls;\n  mobile_arrow_settings* arrow = &env->usr->usrs.arrow_controls;\n', '                           float* dy, float* length, float* width) {\n  mobile_arrow_settings* arrow = &env->usr->usrs.arrow_controls;\n')]

_arrow_patch("app/src/mobile/mobile_controls.c", [STEERING_DEF_PAIR])
_controls = OUTPUT / "app/src/mobile/mobile_controls.c"
_text = _controls.read_text(encoding="utf-8")
if "cfg->joystick_mode" not in _text:
    raise SystemExit("upright arrow: no cfg->joystick_mode left to route")
_controls.write_text(_text.replace("cfg->joystick_mode", "mobile_controls_steering_mode(env)"), encoding="utf-8")
_arrow_patch("app/src/mobile/mobile_controls.c", UNUSED_CFG_PAIRS)
_arrow_patch("app/src/mobile/mobile_controls.h", [STEERING_DECL_PAIR])
_arrow_patch("app/src/game/redraw.c", [REDRAW_PROTO_PAIR, REDRAW_MODE_PAIR])
_arrow_patch("app/src/game/ui_overlay.c", [OVERLAY_MODE_PAIR, LAST_DEATH_DEF_PAIR, LAST_DEATH_DRAW_PAIR])
print("Portrait play: arrow steering only; last death on the minimap")


# Near Original (OM, 2026-10-02; Wyrm Android has the same C): slither's own
# HUD (minimap top-left with "server N", leaderboard in snake colours, no
# stats), fixed original joystick and boost, the original arrow (also a Wyrm
# arrow style, value 5), from the original Main.as. The flag lives in
# HomeMailbox.inc (WyrmIOSSetNearOriginal). Fonts: Nunito Bold / Black from the
# original slither.io app (OFL), copied into the engine's res tree.
NEAR_ORIGINAL_PAIRS = [('app/src/platform/android_update.c', [('                           source.arrow_style <= MOBILE_ARROW_TRIANGLE);\n', '                           source.arrow_style <= MOBILE_ARROW_ORIGINAL);\n')]), ('app/src/platform/android_home.h', [('float android_home_joystick_laser_length(void);\n', "float android_home_joystick_laser_length(void);\n/* Near Original (OM, 2026-10-02): slither's own HUD, joystick, boost and\n   arrow. Set by the app (Home); `server` is the arena's number for the\n   minimap label, 0 when unknown. Display and touch only, nothing is sent\n   differently. */\nvoid android_home_set_near_original(bool on, int server);\nbool android_home_near_original(void);\nint android_home_near_original_server(void);\n")]), ('app/src/user.h', [('    ImFont* body_font[NUM_FONT_SIZES];\n', "    ImFont* body_font[NUM_FONT_SIZES];\n    /* Near Original: slither's own faces (Nunito Bold / Black). */\n    ImFont* nunito_bold;\n    ImFont* nunito_black;\n")]), ('app/src/imgui_setup.c', [('  io->ConfigFlags |= ImGuiConfigFlags_DockingEnable;\n', '  /* Near Original (OM, 2026-10-02): the original game\'s own faces, from the\n     slither.io app itself (OFL). Sized per draw call. */\n  usr->imgui_data.nunito_bold = ImFontAtlas_AddFontFromFileTTF(\n      io->Fonts, "app/res/fonts/nunito_bold.ttf", 22, NULL, NULL);\n  usr->imgui_data.nunito_black = ImFontAtlas_AddFontFromFileTTF(\n      io->Fonts, "app/res/fonts/nunito_black.ttf", 22, NULL, NULL);\n\n  io->ConfigFlags |= ImGuiConfigFlags_DockingEnable;\n')]), ('app/src/game/user_settings.h', [('  MOBILE_ARROW_TRIANGLE = 4\n', "  MOBILE_ARROW_TRIANGLE = 4,\n  /* slither's own arrow (Near Original, 2026-10-02). Older builds clamp it. */\n  MOBILE_ARROW_ORIGINAL = 5\n")]), ('app/src/game/user_settings.c', [('      usr_settings->arrow_style > MOBILE_ARROW_TRIANGLE) {\n', '      usr_settings->arrow_style > MOBILE_ARROW_ORIGINAL) {\n')]), ('app/src/platform/android_settings.c', [('    {"arrow.style", "controls.arrow", "Arrow style", "", SETTING_ENUM, 0, 4,\n     "Classic|Classic wide|Needle|Blade|Triangle", OWNER_SETTINGS,', '    {"arrow.style", "controls.arrow", "Arrow style", "", SETTING_ENUM, 0, 5,\n     "Classic|Classic wide|Needle|Blade|Triangle|Original", OWNER_SETTINGS,')]), ('app/src/mobile/mobile_controls.c', [('#include "mobile_hotkeys.h"\n', '#include "mobile_hotkeys.h"\n#include "../platform/android_home.h"\n'), ('static void normalized_position(tenv* env, float nx, float ny, float* x,\n                                float* y) {', "/*\n * Near Original (OM, 2026-10-02): slither's own controls, from the original\n * game's Main.as. Its unit is the short side / 480 (`force_game_scale`).\n * Fixed joystick at (150u, H - 130u), boost at (W - 140u, H - 140u), both\n * mirrored when the joystick is on the right (Wyrm's Handedness = the\n * original's flip). Display and touch only.\n */\nstatic float original_unit(tenv* env) {\n  int short_side = env->wnd->size[0] < env->wnd->size[1] ? env->wnd->size[0]\n                                                         : env->wnd->size[1];\n  return short_side / 480.0f;\n}\n\nstatic bool original_joystick_right(tenv* env) {\n  return env->usr->usrs.mobile_controls.handedness != MOBILE_LEFT_HANDED;\n}\n\nstatic void original_joystick_centre(tenv* env, float* x, float* y) {\n  float u = original_unit(env);\n  *x = original_joystick_right(env) ? env->wnd->size[0] - 150.0f * u\n                                    : 150.0f * u;\n  *y = env->wnd->size[1] - 130.0f * u;\n}\n\nstatic void original_boost_centre(tenv* env, float* x, float* y) {\n  float u = original_unit(env);\n  *x = original_joystick_right(env) ? 140.0f * u\n                                    : env->wnd->size[0] - 140.0f * u;\n  *y = env->wnd->size[1] - 140.0f * u;\n}\n\n/* The boost button's alpha (0.2 idle, 0.4 boosting) and the arrow's boost\n   glow (`accel_a`, `accel_fr`), stepped once a frame. */\nstatic float original_boost_alpha = 0.3f;\nstatic float original_accel_a = 0.0f;\nstatic float original_accel_fr = 0.0f;\n\nstatic void normalized_position(tenv* env, float nx, float ny, float* x,\n                                float* y) {"), ('  float d = 58.0f * sc * gdata->data.gsc * arrow->separation;', '  /* Near Original: the original start distance (separation 1). */\n  float separation = android_home_near_original() ? 1.0f : arrow->separation;\n  float d = 58.0f * sc * gdata->data.gsc * separation;'), ('bool mobile_controls_process_event(tenv* env, const void* raw_event) {\n  const SDL_Event* event = raw_event;', "/* The original's steering: the angle from the fixed joystick centre to the\n   finger, wherever it is on the joystick's half. */\nstatic void original_aim(tenv* env, float x, float y) {\n  mobile_controls_state* state = &env->usr->mobile_controls;\n  float cx, cy;\n  original_joystick_centre(env, &cx, &cy);\n  float dx = x - cx;\n  float dy = y - cy;\n  float length = sqrtf(dx * dx + dy * dy);\n  if (length < 0.5f) return;\n  state->joystick_axis[0] = dx / length;\n  state->joystick_axis[1] = dy / length;\n  state->aim_valid = true;\n}\n\n/* Near Original touch (Main.as touch begin): sideways the boost button takes\n   a finger within 160u of its centre; the arrow takes the first finger\n   anywhere; the joystick takes a finger on its half; upright a second finger\n   boosts (the original hides the button there). Releases go through the\n   normal path. */\nstatic bool original_touch(tenv* env, const SDL_Event* event, uint64_t finger,\n                           float x, float y) {\n  mobile_controls_state* state = &env->usr->mobile_controls;\n  bool upright = env->wnd->size[1] > env->wnd->size[0];\n  bool arrow = mobile_controls_steering_mode(env) == MOBILE_STEERING_ARROW;\n  if (event->type == SDL_EVENT_FINGER_DOWN) {\n    if (!state->zoom_down && inside_zoom(env, x, y)) {\n      state->zoom_down = true;\n      state->zoom_finger = finger;\n      set_zoom_from_touch(env, x, y);\n      return true;\n    }\n    if (!upright && !state->boost_down) {\n      float bx, by;\n      original_boost_centre(env, &bx, &by);\n      if (inside_circle(x, y, bx, by, 160.0f * original_unit(env))) {\n        state->boost_down = true;\n        state->boost_finger = finger;\n        state->boost_origin[0] = bx;\n        state->boost_origin[1] = by;\n        return true;\n      }\n    }\n    if (arrow) {\n      if (!state->joystick_down) {\n        state->joystick_down = true;\n        state->joystick_finger = finger;\n        state->joystick_origin[0] = x;\n        state->joystick_origin[1] = y;\n        state->arrow_drag_distance = 0.0f;\n        arrow_seed(env, x, y);\n        return true;\n      }\n      if (upright && !state->boost_down && state->joystick_finger != finger) {\n        state->boost_down = true;\n        state->boost_finger = finger;\n        state->boost_origin[0] = x;\n        state->boost_origin[1] = y;\n      }\n      return true;\n    }\n    bool on_side = original_joystick_right(env)\n                       ? x >= env->wnd->size[0] * 0.5f\n                       : x < env->wnd->size[0] * 0.5f;\n    if (on_side && !state->joystick_down) {\n      float cx, cy;\n      original_joystick_centre(env, &cx, &cy);\n      state->joystick_down = true;\n      state->joystick_finger = finger;\n      state->joystick_origin[0] = cx;\n      state->joystick_origin[1] = cy;\n      original_aim(env, x, y);\n    }\n    return true;\n  }\n  if (event->type == SDL_EVENT_FINGER_MOTION) {\n    if (state->joystick_down && state->joystick_finger == finger) {\n      if (arrow)\n        update_arrow(env, x, y);\n      else\n        original_aim(env, x, y);\n      return true;\n    }\n    if (state->zoom_down && state->zoom_finger == finger) {\n      set_zoom_from_touch(env, x, y);\n      return true;\n    }\n  }\n  return false;\n}\n\nbool mobile_controls_process_event(tenv* env, const void* raw_event) {\n  const SDL_Event* event = raw_event;"), ('  if (event->type == SDL_EVENT_FINGER_DOWN) {\n    float mid = env->wnd->size[0] * 0.5f;', "  /* Near Original: slither's own fixed controls (releases fall through). */\n  if (android_home_near_original() && event->type != SDL_EVENT_FINGER_UP &&\n      event->type != SDL_EVENT_FINGER_CANCELED)\n    return original_touch(env, event, finger, x, y);\n\n  if (event->type == SDL_EVENT_FINGER_DOWN) {\n    float mid = env->wnd->size[0] * 0.5f;"), ('    float ease = clampf(1.0f - arrow->smoothness, 0.05f, 0.95f);', "    /* Near Original: slither's own 0.6 catch-up (smoothness 0.4). */\n    float smoothness = android_home_near_original() ? 0.4f : arrow->smoothness;\n    float ease = clampf(1.0f - smoothness, 0.05f, 0.95f);"), ('      if (state->arrow_dead > 1.0f) state->arrow_dead = 1.0f;\n    }\n  }\n', "      if (state->arrow_dead > 1.0f) state->arrow_dead = 1.0f;\n    }\n\n    /* Near Original: the boost button's alpha (Main.as: 0.2 idle, up to 0.4\n       while boosting, 0.01 a frame) and the arrow's boost glow (accel_a\n       +0.02 / -0.03 a frame, accel_fr +0.15 while boosting). */\n    if (state->boost_down) {\n      original_boost_alpha += 0.01f * vfr;\n      if (original_boost_alpha > 0.4f) original_boost_alpha = 0.4f;\n      original_accel_a += 0.02f * vfr;\n      if (original_accel_a > 1.0f) original_accel_a = 1.0f;\n      original_accel_fr += 0.15f * vfr;\n    } else {\n      original_boost_alpha -= 0.01f * vfr;\n      if (original_boost_alpha < 0.2f) original_boost_alpha = 0.2f;\n      original_accel_a -= 0.03f * vfr;\n      if (original_accel_a < 0.0f) original_accel_a = 0.0f;\n    }\n  }\n"), ('  float drift = 260.0f * scale * powf(state->arrow_dead, 2.5f);', "  /* Near Original: the release drift is in the original's unit. */\n  float drift = 260.0f * (android_home_near_original() ? original_unit(env) : scale) *\n                powf(state->arrow_dead, 2.5f);"), ('  static const float triangle_x[] = {0.82f, -0.64f, -0.64f};\n  static const float triangle_y[] = {0.00f, -0.26f, 0.26f};\n', "  static const float triangle_x[] = {0.82f, -0.64f, -0.64f};\n  static const float triangle_y[] = {0.00f, -0.26f, 0.26f};\n  /* slither's own arrow (Main.as, 64 px shape): shaft, then the head. */\n  static const float original_x[] = {-0.56f, -0.56f, 0.00f, 0.00f,\n                                     0.56f, 0.00f, 0.00f};\n  static const float original_y[] = {-0.3155f, 0.3155f, 0.2227f, 0.7423f,\n                                     0.00f, -0.7423f, -0.2227f};\n"), ('    case MOBILE_ARROW_TRIANGLE:\n      return (mobile_arrow_shape){3, triangle_x, triangle_y};\n', '    case MOBILE_ARROW_TRIANGLE:\n      return (mobile_arrow_shape){3, triangle_x, triangle_y};\n    case MOBILE_ARROW_ORIGINAL:\n      return (mobile_arrow_shape){7, original_x, original_y};\n'), ('static void draw_zoom(tenv* env, ImDrawList* dl, bool editor) {', '/* ---- Near Original drawing (Main.as textures, drawn here) ---- */\n\n/* A soft dark halo outside a disc: DropShadowFilter(0, 90, black, 1, 14, 14). */\nstatic void original_halo(ImDrawList* dl, float cx, float cy, float radius,\n                          float spread, float alpha) {\n  for (int i = 0; i < 6; ++i) {\n    float t = (i + 0.5f) / 6.0f;\n    float fade = (1.0f - t) * (1.0f - t);\n    ImDrawList_AddCircle(dl, (ImVec2){cx, cy}, radius + spread * t,\n                         color_u32(0, 0, 0, alpha * 0.55f * fade), 48,\n                         spread / 6.0f + 0.5f);\n  }\n}\n\n/* The snake\'s arrow colour (Main.as 20085-20120): a quarter of white, three\n   quarters of the snake\'s colour, with the original\'s fixed overrides. */\nstatic ImU32 original_arrow_colour(tenv* env, float alpha) {\n  game_data* gdata = &env->usr->gdata;\n  snake* own = get_snake(gdata, gdata->data.snake_id);\n  int cv = own ? own->cv : 0;\n  if (cv < 0 || cv >= NUM_COLOR_GROUPS) cv = 0;\n  float r, g, b;\n  switch (cv) {\n    case 29: r = 0xCC; g = 0xCC; b = 0xCC; break;\n    case 30: r = 0x40; g = 0x40; b = 0xFF; break;\n    case 31: r = 0xFF; g = 0x40; b = 0x40; break;\n    case 32: r = 0xFF; g = 0xFF; b = 0x40; break;\n    case 33: r = 0xFF; g = 0x90; b = 0x40; break;\n    case 34: r = 0xFF; g = 0x40; b = 0xFF; break;\n    case 35: r = 0x50; g = 0xFF; b = 0x50; break;\n    case 36: r = 0xFF; g = 0x40; b = 0x40; break;\n    case 41: r = 0x80; g = 0x80; b = 0xFF; break;\n    default: {\n      vec3s c = gdata->cg_colors[cv];\n      float cr = roundf(c.x * 256.0f), cg = roundf(c.y * 256.0f),\n            cb = roundf(c.z * 256.0f);\n      r = roundf(64.0f + 0.75f * (cr > 255.0f ? 255.0f : cr));\n      g = roundf(64.0f + 0.75f * (cg > 255.0f ? 255.0f : cg));\n      b = roundf(64.0f + 0.75f * (cb > 255.0f ? 255.0f : cb));\n    }\n  }\n  if (r > 255.0f) r = 255.0f;\n  if (g > 255.0f) g = 255.0f;\n  if (b > 255.0f) b = 255.0f;\n  return color_u32(r / 255.0f, g / 255.0f, b / 255.0f, alpha);\n}\n\n/* slither\'s arrow: the 64 px polygon from its left-middle pivot, a 9 px black\n   mitred outline under a fill in the snake\'s colour, a soft shadow, scale\n   0.5 + 0.25 accel_a (in units, times the player\'s arrow size), and an extra\n   pulsing copy while boosting. */\nstatic void draw_original_arrow(tenv* env, ImDrawList* dl) {\n  float ax, ay, dx, dy, length, width;\n  if (!arrow_geometry(env, &ax, &ay, &dx, &dy, &length, &width)) return;\n  float alpha = env->usr->mobile_controls.arrow_opacity;\n  if (alpha > 1.0f) alpha = 1.0f;\n  float size = env->usr->usrs.arrow_controls.size;\n  if (!(size > 0.0f)) size = 1.0f;\n  float s = (0.5f + 0.25f * original_accel_a) * original_unit(env) * size;\n  float px = -dy;\n  float py = dx;\n  static const float shape_x[] = {15.0f, 15.0f, 41.0f, 41.0f, 67.0f, 41.0f, 41.0f};\n  static const float shape_y[] = {-10.88f, 10.88f, 7.68f, 25.6f, 0.0f, -25.6f, -7.68f};\n  ImVec2 p[7];\n  for (int i = 0; i < 7; ++i)\n    p[i] = (ImVec2){ax + dx * shape_x[i] * s + px * shape_y[i] * s,\n                    ay + dy * shape_x[i] * s + py * shape_y[i] * s};\n  /* The texture\'s DropShadowFilter(0, 90, black, 1, 12, 12, 1, 3): a soft\n     black halo (sigma ~6 texture px) around the outlined arrow. Nested strokes,\n     widest first, each set so the pile at a distance x outside the 9 px outline\n     reads 0.5 erfc(x / (sigma sqrt 2)) of the arrow\'s alpha. */\n  {\n    const int bands = 8;\n    const float sigma = 6.0f;\n    float before = 0.0f;\n    for (int j = bands; j >= 1; --j) {\n      float x = (j - 0.5f) * (3.0f * sigma / bands);\n      float want = alpha * 0.5f * erfcf(x / (sigma * 1.41421356f));\n      float a = before >= 0.999f ? 0.0f : 1.0f - (1.0f - want) / (1.0f - before);\n      if (a > 0.003f)\n        ImDrawList_AddPolyline(dl, p, 7, color_u32(0, 0, 0, a), ImDrawFlags_Closed,\n                               (9.0f + 2.0f * j * (3.0f * sigma / bands)) * s);\n      if (want > before) before = want;\n    }\n  }\n  ImDrawList_AddPolyline(dl, p, 7, color_u32(0, 0, 0, alpha),\n                         ImDrawFlags_Closed, 9.0f * s);\n  ImU32 fill = original_arrow_colour(env, alpha);\n  ImVec2 shaft[4] = {p[0], p[1], p[2], p[6]};\n  ImVec2 head[3] = {p[5], p[4], p[3]};\n  ImDrawList_AddConvexPolyFilled(dl, shaft, 4, fill);\n  ImDrawList_AddConvexPolyFilled(dl, head, 3, fill);\n  float glow = alpha * original_accel_a *\n               (0.5f + 0.5f * cosf(original_accel_fr));\n  if (glow > 0.004f) {\n    /* The ADD copy (arrow_add_ii): over the fill, the arrow\'s colour added at\n       `glow`, drawn as the colour doubled at that alpha. */\n    ImVec4 base;\n    igColorConvertU32ToFloat4(&base, fill);\n    ImU32 bright = color_u32(base.x * 2.0f > 1.0f ? 1.0f : base.x * 2.0f,\n                             base.y * 2.0f > 1.0f ? 1.0f : base.y * 2.0f,\n                             base.z * 2.0f > 1.0f ? 1.0f : base.z * 2.0f, glow);\n    ImDrawList_AddConvexPolyFilled(dl, shaft, 4, bright);\n    ImDrawList_AddConvexPolyFilled(dl, head, 3, bright);\n  }\n}\n\n/* The joystick (Main.as 26514-26539, 28315-28326): a #808080 disc r 64 at\n   scale 0.7 and a white knob r 48 at scale 0.375, both with a black halo and\n   alpha 0.35; the knob sits 24u from the centre toward the steering angle. */\nstatic void draw_original_joystick(tenv* env, ImDrawList* dl) {\n  mobile_controls_state* state = &env->usr->mobile_controls;\n  float u = original_unit(env);\n  float cx, cy;\n  original_joystick_centre(env, &cx, &cy);\n  float base = 64.0f * 0.7f * u;\n  original_halo(dl, cx, cy, base, 7.0f * 0.7f * u, 0.35f);\n  ImDrawList_AddCircleFilled(dl, (ImVec2){cx, cy}, base,\n                             color_u32(0.502f, 0.502f, 0.502f, 0.35f), 48);\n  float kx = cx, ky = cy;\n  if (state->aim_valid) {\n    kx += state->joystick_axis[0] * 24.0f * u;\n    ky += state->joystick_axis[1] * 24.0f * u;\n  }\n  float knob = 48.0f * 0.375f * u;\n  original_halo(dl, kx, ky, knob, 7.0f * 0.375f * u, 0.35f);\n  ImDrawList_AddCircleFilled(dl, (ImVec2){kx, ky}, knob,\n                             color_u32(1, 1, 1, 0.35f), 32);\n}\n\n/* The boost button, "boostie" (sheet0 of the original, 294 px, scale 0.35):\n   a #A0A0A0 disc r 110 with a soft black halo and a white triangle with a\n   shadow under it. Measured from the original image. */\nstatic void draw_original_boost(tenv* env, ImDrawList* dl) {\n  float cx, cy;\n  original_boost_centre(env, &cx, &cy);\n  float k = 0.35f * original_unit(env);\n  float a = original_boost_alpha;\n  static const float halo[] = {0.42f, 0.33f, 0.25f, 0.18f, 0.13f, 0.08f,\n                               0.05f, 0.02f, 0.01f};\n  for (int i = 0; i < 9; ++i)\n    ImDrawList_AddCircle(dl, (ImVec2){cx, cy}, (110.0f + 2.0f + 4.0f * i) * k,\n                         color_u32(0, 0, 0, a * halo[i]), 48, 4.0f * k + 0.5f);\n  ImDrawList_AddCircleFilled(dl, (ImVec2){cx, cy}, 110.0f * k,\n                             color_u32(0.627f, 0.627f, 0.627f, a), 48);\n  for (int i = 1; i <= 4; ++i) {\n    float drop = (2.0f + 4.0f * i) * k;\n    ImDrawList_AddTriangleFilled(\n        dl, (ImVec2){cx, cy - 41.5f * k + drop},\n        (ImVec2){cx + 56.0f * k, cy + 25.5f * k + drop},\n        (ImVec2){cx - 56.0f * k, cy + 25.5f * k + drop},\n        color_u32(0, 0, 0, a * 0.07f));\n  }\n  ImDrawList_AddTriangleFilled(dl, (ImVec2){cx, cy - 41.5f * k},\n                               (ImVec2){cx + 56.0f * k, cy + 25.5f * k},\n                               (ImVec2){cx - 56.0f * k, cy + 25.5f * k},\n                               color_u32(1, 1, 1, a));\n}\n\nstatic void draw_original_controls(tenv* env, ImDrawList* dl) {\n  if (mobile_controls_steering_mode(env) == MOBILE_STEERING_ARROW)\n    draw_original_arrow(env, dl);\n  else\n    draw_original_joystick(env, dl);\n  /* Upright the original has no button: a second finger boosts. */\n  if (env->wnd->size[0] >= env->wnd->size[1]) draw_original_boost(env, dl);\n}\n\nstatic void draw_zoom(tenv* env, ImDrawList* dl, bool editor) {'), ('  float jx, jy, bx, by;\n  normalized_position(env, cfg->joystick_x, cfg->joystick_y, &jx, &jy);\n  normalized_position(env, cfg->boost_x, cfg->boost_y, &bx, &by);\n\n  if (mobile_controls_steering_mode(env) == MOBILE_STEERING_ARROW) {\n    draw_arrow(env, dl);', "  /* Near Original: slither's own controls; the zoom bar and the on-screen\n     buttons stay the player's. */\n  if (android_home_near_original()) {\n    draw_original_controls(env, dl);\n    draw_zoom(env, dl, false);\n    mobile_hotkeys_draw_gameplay(env);\n    return;\n  }\n  float jx, jy, bx, by;\n  normalized_position(env, cfg->joystick_x, cfg->joystick_y, &jx, &jy);\n  normalized_position(env, cfg->boost_x, cfg->boost_y, &bx, &by);\n\n  if (mobile_controls_steering_mode(env) == MOBILE_STEERING_ARROW) {\n    draw_arrow(env, dl);")]), ('app/src/game/ui_overlay.c', [('#include "../platform/android_home.h"\n', '#include "../platform/android_home.h"\n#include "../ui/ui_theme.h"\n#include "backgrounds.h"\n'), ('void ui_overlay(tenv* env) {\n  tuser_data* usr = env->usr;', '/* ---- Near Original (OM, 2026-10-02): slither\'s own HUD, Main.as ---- */\n\nstatic float original_lb_fade = 0.0f;\n\nstatic ImVec2 original_text_size(ImFont* font, float size, const char* text) {\n  ImVec2 out;\n  igPushFont(font, size);\n  igCalcTextSize(&out, text, NULL, false, -1);\n  igPopFont();\n  return out;\n}\n\n/*\n * One leaderboard string as the original draws it (Main.as drawText and the\n * glyph sheets, 26865-27030). The glyphs were cut at 52 px with\n * DropShadowFilter(0, 90, black, 1, 7, 7, strength 24) = a solid black outline\n * about 6 px wide, then DropShadowFilter(3, 90, black, 0.75, 8, 8) = a soft\n * shadow 3 px below. The board draws that outlined glyph, tinted with the\n * snake\'s colour, at `alpha`, and the bare face again ADDITIVELY at the same\n * alpha (highscore_add_batch). Over the face the sum is bg(1 - a) + 2ca, so the\n * face is drawn here in twice its colour; that is why it reads on any floor.\n */\nstatic void original_text(ImDrawList* draw, ImFont* font, float size,\n                          ImVec2 pos, vec3s colour, float alpha,\n                          const char* text) {\n  if (alpha <= 0.004f) return;\n  float f = size / 52.0f;\n  float outline = 6.0f * f;\n  float drop = 3.0f * f;\n  /* Stamps overlap about three deep: each is weaker so the pile reads as alpha. */\n  float stamp = 1.0f - powf(1.0f - (alpha > 0.999f ? 0.999f : alpha), 1.0f / 3.0f);\n  ImU32 shadow = igColorConvertFloat4ToU32((ImVec4){0, 0, 0, stamp * 0.75f * 0.45f});\n  ImU32 black = igColorConvertFloat4ToU32((ImVec4){0, 0, 0, stamp});\n  for (int i = 0; i < 8; ++i) {\n    float a = 6.2831853f * (i + 0.5f) / 8.0f;\n    float spread = outline + 4.0f * f;\n    ImDrawList_AddText_FontPtr(\n        draw, font, size,\n        (ImVec2){pos.x + cosf(a) * spread, pos.y + drop + sinf(a) * spread},\n        shadow, text, NULL, 0, NULL);\n  }\n  for (int i = 0; i < 12; ++i) {\n    float a = 6.2831853f * i / 12.0f;\n    ImDrawList_AddText_FontPtr(\n        draw, font, size,\n        (ImVec2){pos.x + cosf(a) * outline, pos.y + sinf(a) * outline},\n        black, text, NULL, 0, NULL);\n  }\n  for (int i = 0; i < 6; ++i) {\n    float a = 6.2831853f * (i + 0.5f) / 6.0f;\n    ImDrawList_AddText_FontPtr(\n        draw, font, size,\n        (ImVec2){pos.x + cosf(a) * outline * 0.5f, pos.y + sinf(a) * outline * 0.5f},\n        black, text, NULL, 0, NULL);\n  }\n  float r = colour.x * 2.0f, g = colour.y * 2.0f, b = colour.z * 2.0f;\n  ImU32 face = igColorConvertFloat4ToU32((ImVec4){r > 1.0f ? 1.0f : r,\n                                                  g > 1.0f ? 1.0f : g,\n                                                  b > 1.0f ? 1.0f : b, alpha});\n  ImDrawList_AddText_FontPtr(draw, font, size, pos, face, text, NULL, 0, NULL);\n}\n\n/*\n * The minimap disc\'s colour per floor. The original fills the disc with its\n * floor image, scaled by max(1, 512 / short side) x 0.5 and blurred 64\n * (Main.as setMinimapSize 18568-18740); the classic floor first x0.6 + 4, then\n * light floors x0.75 and the rest x1.35 + 12. Measured offline from the same\n * images (mean over the disc after that blur); Wyrm\'s own floors as dark ones,\n * None as black. Unknown ids fall back to the original\'s dark default.\n */\nstatic const struct {\n  const char* id;\n  unsigned char r, g, b;\n} ORIGINAL_MINIMAP_FLOOR[] = {\n    {"wyrm", 40, 48, 62},          {"none", 12, 12, 12},\n    {"classic", 39, 46, 55},       {"bgee2", 27, 44, 62},\n    {"asanoha", 82, 33, 39},       {"seigaiha", 74, 113, 146},\n    {"graygrid", 126, 126, 126},   {"rizz", 159, 124, 175},\n    {"usastar", 39, 63, 128},      {"circuits", 33, 29, 60},\n    {"circuits2", 37, 33, 81},     {"hexice", 61, 96, 124},\n    {"hexb", 27, 37, 72},          {"hearts", 176, 95, 114},\n    {"leaves", 131, 78, 51},       {"paint", 144, 110, 100},\n    {"snakey", 95, 108, 71},       {"stainedglass", 108, 72, 76},\n    {"kitties", 155, 95, 159},     {"bluecube", 67, 81, 177},\n    {"purplecube", 120, 40, 161},  {"redcube", 167, 60, 54},\n    {"black", 12, 12, 12},         {"wyrm_midnight", 28, 42, 65},\n    {"wyrm_carbon", 46, 50, 57},   {"wyrm_abyss", 23, 50, 57},\n    {"wyrm_nebula", 23, 22, 35},   {"wyrm_dotgrid", 34, 36, 40},\n    {"wyrm_contours", 32, 44, 51}, {"wyrm_scales", 35, 51, 43},\n};\n\nstatic vec3s original_minimap_floor(int floor) {\n  const char* id = BACKGROUNDS[background_clamp(floor)].id;\n  int count = (int)(sizeof(ORIGINAL_MINIMAP_FLOOR) / sizeof(ORIGINAL_MINIMAP_FLOOR[0]));\n  for (int i = 0; i < count; ++i)\n    if (strcmp(ORIGINAL_MINIMAP_FLOOR[i].id, id) == 0)\n      return (vec3s){{ORIGINAL_MINIMAP_FLOOR[i].r / 255.0f,\n                      ORIGINAL_MINIMAP_FLOOR[i].g / 255.0f,\n                      ORIGINAL_MINIMAP_FLOOR[i].b / 255.0f}};\n  return (vec3s){{27 / 255.0f, 44 / 255.0f, 62 / 255.0f}};\n}\n\n/*\n * The minimap\'s DropShadowFilter(3, 90, black, 0.5, 12, 12, 1, 3): the disc\'s\n * silhouette moved down `drop` and blurred (three box passes of 12 = sigma ~6),\n * seen only where the disc itself is not (the bitmap is opaque inside the disc).\n * Thin rings, each at that distance\'s shadow strength, cut away over the disc.\n */\nstatic void original_disc_shadow(ImDrawList* draw, ImVec2 c, float R,\n                                 float drop, float sigma, float alpha) {\n  const int segments = 64;\n  float step = sigma * 0.35f;\n  if (step < 1.0f) step = 1.0f;\n  ImVec2 s = {c.x, c.y + drop};\n  float keep = (R + step * 0.5f) * (R + step * 0.5f);\n  for (float d = -drop; d < sigma * 3.0f; d += step) {\n    float mid = d + step * 0.5f;\n    float rho = R + mid;\n    if (rho <= 0.0f) continue;\n    float a = alpha * 0.5f * erfcf(mid / (sigma * 1.41421356f));\n    if (a < 0.003f) continue;\n    ImU32 col = igColorConvertFloat4ToU32((ImVec4){0, 0, 0, a});\n    for (int i = 0; i < segments; ++i) {\n      float a0 = 6.2831853f * i / segments;\n      float a1 = 6.2831853f * (i + 1) / segments;\n      ImVec2 p0 = {s.x + cosf(a0) * rho, s.y + sinf(a0) * rho};\n      ImVec2 p1 = {s.x + cosf(a1) * rho, s.y + sinf(a1) * rho};\n      float mx = (p0.x + p1.x) * 0.5f - c.x;\n      float my = (p0.y + p1.y) * 0.5f - c.y;\n      if (mx * mx + my * my <= keep) continue;\n      ImDrawList_AddLine(draw, p0, p1, col, step + 0.5f);\n    }\n  }\n}\n\n/* A pie slice of the minimap disc, from angle a0 to a1 (radians, y down). */\nstatic void original_wedge(ImDrawList* draw, ImVec2 c, float r, float a0,\n                           float a1, ImU32 colour) {\n  ImVec2 points[18];\n  points[0] = c;\n  for (int i = 0; i <= 16; ++i) {\n    float a = a0 + (a1 - a0) * i / 16.0f;\n    points[i + 1] = (ImVec2){c.x + cosf(a) * r, c.y + sinf(a) * r};\n  }\n  ImDrawList_AddConvexPolyFilled(draw, points, 18, colour);\n}\n\n/*\n * The original HUD (Main.as): the minimap top-left (x 24 px, y 8 px, plus the\n * notch upright; scale 0.75u; a #202630 disc with two lighter quarters, alpha\n * 0.7, a soft shadow, "server N" in Nunito Bold 18 above it; white cells at\n * 0.475 and your position as a white dot) and the leaderboard top-right\n * (rows of 14u, text 11u in Nunito Bold, each in that snake\'s colour with a\n * black outline; no title). Wyrm\'s stats and bearing are not drawn.\n */\nstatic void draw_original_hud(tenv* env, ImDrawList* draw) {\n  tuser_data* usr = env->usr;\n  game_data* gdata = &usr->gdata;\n  user_settings* usrs = &usr->usrs;\n  float W = env->ctx->size[0];\n  float H = env->ctx->size[1];\n  float u = (W < H ? W : H) / 480.0f;\n  bool portrait = H > W;\n  float notch = 0.0f;\n  if (portrait) {\n    ui_safe_area safe = ui_theme_safe_area(env);\n    notch = safe.y;\n    /* SDL gives the safe area in window coordinates: points on iOS (a third\n       of the pixels on a 3x phone), pixels on Android. The HUD is in pixels. */\n    if (env->wnd && env->wnd->handle) {\n      int points_w = 0, points_h = 0;\n      SDL_GetWindowSize(env->wnd->handle, &points_w, &points_h);\n      if (points_h > 0 && env->wnd->size[1] > points_h)\n        notch *= (float)env->wnd->size[1] / (float)points_h;\n    }\n    if (notch > 90.0f * u) notch = 90.0f * u;\n    if (notch < 0.0f) notch = 0.0f;\n  }\n  ImFont* bold = usr->imgui_data.nunito_bold\n                     ? usr->imgui_data.nunito_bold\n                     : usr->imgui_data.regular_font_bold[1];\n\n  /* ---- minimap ---- */\n  int mmsz = gdata->data.mmsz > 0 ? gdata->data.mmsz : 80;\n  if (mmsz > MAX_MINIMAP_SIZE) mmsz = MAX_MINIMAP_SIZE;\n  float k = 0.75f * u;\n  const float pad = 12.0f;\n  float side = mmsz + pad * 2.0f;\n  float ox = 24.0f;\n  float oy = 8.0f + notch;\n  float r = mmsz * 0.5f;\n  ImVec2 c = {ox + side * 0.5f * k, oy + (side * 0.5f + 23.0f) * k};\n  float R = r * k;\n\n  /* The bitmap\'s shadow (0.5) under the bitmap\'s own alpha (0.7). */\n  original_disc_shadow(draw, c, R, 3.0f * k, 6.0f * k, 0.5f * 0.7f);\n  /* The disc: the floor, blurred (see ORIGINAL_MINIMAP_FLOOR), with the top-left\n     and bottom-right quarters lifted by #202020 (ADD); the bitmap at 0.7. */\n  vec3s floor_rgb = original_minimap_floor(usrs->arena_background);\n  float lift = 32.0f / 255.0f;\n  ImU32 dark = igColorConvertFloat4ToU32((ImVec4){floor_rgb.x, floor_rgb.y, floor_rgb.z, 0.7f});\n  ImU32 light = igColorConvertFloat4ToU32((ImVec4){\n      floor_rgb.x + lift > 1.0f ? 1.0f : floor_rgb.x + lift,\n      floor_rgb.y + lift > 1.0f ? 1.0f : floor_rgb.y + lift,\n      floor_rgb.z + lift > 1.0f ? 1.0f : floor_rgb.z + lift, 0.7f});\n  const float pi = 3.14159265f;\n  original_wedge(draw, c, R, pi, 1.5f * pi, light);\n  original_wedge(draw, c, R, 1.5f * pi, 2.0f * pi, dark);\n  original_wedge(draw, c, R, 0.0f, 0.5f * pi, light);\n  original_wedge(draw, c, R, 0.5f * pi, pi, dark);\n\n  int server = android_home_near_original_server();\n  if (server > 0) {\n    char label[32];\n    snprintf(label, sizeof(label), "server %d", server);\n    float size = 18.0f * k;\n    ImVec2 ts = original_text_size(bold, size, label);\n    ImVec2 at = {ox + (side * k - ts.x) * 0.5f, oy + 6.0f * k};\n    ImU32 hush = igColorConvertFloat4ToU32((ImVec4){0, 0, 0, 0.5f * 0.7f * 0.75f * 0.22f});\n    for (int i = 0; i < 6; ++i) {\n      float a = 6.2831853f * i / 6.0f;\n      ImDrawList_AddText_FontPtr(\n          draw, bold, size,\n          (ImVec2){at.x + cosf(a) * 3.0f * k, at.y + 3.0f * k + sinf(a) * 3.0f * k},\n          hush, label, NULL, 0, NULL);\n    }\n    ImDrawList_AddText_FontPtr(\n        draw, bold, size, at,\n        igColorConvertFloat4ToU32((ImVec4){1, 1, 1, 0.75f * 0.7f}), label, NULL, 0, NULL);\n  }\n\n  /* The map: one rect per run of set cells in a row. */\n  if (gdata->data.mmsz > 0) {\n    ImU32 cell = igColorConvertFloat4ToU32((ImVec4){1, 1, 1, 0.475f});\n    float left = ox + pad * k;\n    float top = oy + (pad + 23.0f) * k;\n    for (int y = 0; y < mmsz; ++y) {\n      const uint8_t* row = gdata->data.mm_data + y * MAX_MINIMAP_SIZE;\n      int x = 0;\n      while (x < mmsz) {\n        if (!row[x]) { ++x; continue; }\n        int start = x;\n        while (x < mmsz && row[x]) ++x;\n        ImDrawList_AddRectFilled(draw, (ImVec2){left + start * k, top + y * k},\n                                 (ImVec2){left + x * k, top + (y + 1) * k}, cell, 0, 0);\n      }\n    }\n  }\n\n  float world = gdata->data.flux_grd;\n  if (world > 1.0f) {\n    int count = tdarray_length(gdata->data.snakes);\n    if (count) {\n      snake* me = gdata->data.snakes + (count - 1);\n      if (me->local_player && gdata->data.snake_id == me->id) {\n        float nx = (me->xx + me->fx - gdata->data.grd) / world;\n        float ny = (me->yy + me->fy - gdata->data.grd) / world;\n        ImVec2 dot = {c.x + nx * R, c.y + ny * R};\n        ImDrawList_AddCircleFilled(draw, dot, 3.0f * k + 1.0f * k,\n                                   igColorConvertFloat4ToU32((ImVec4){0, 0, 0, 0.66f}), 16);\n        ImDrawList_AddCircleFilled(draw, dot, 3.0f * k,\n                                   igColorConvertFloat4ToU32((ImVec4){1, 1, 1, 1}), 16);\n      }\n    }\n    /* The previous run\'s death dot, on this map\'s geometry. */\n    if (last_death_valid && !gdata->ai_mode && !ai_mode_editor_bare()) {\n      float nx = (last_death_x - gdata->data.grd) / world;\n      float ny = (last_death_y - gdata->data.grd) / world;\n      float reach = sqrtf(nx * nx + ny * ny);\n      if (reach > 1.0f) { nx /= reach; ny /= reach; }\n      ImVec2 dot = {c.x + nx * R, c.y + ny * R};\n      ImDrawList* front = igGetForegroundDrawList_ViewportPtr(NULL);\n      ImDrawList_AddCircleFilled(front, dot, 3.0f * k + 2.0f,\n                                 igColorConvertFloat4ToU32((ImVec4){0, 0, 0, 0.70f}), 20);\n      ImDrawList_AddCircleFilled(front, dot, 3.0f * k,\n                                 igColorConvertFloat4ToU32((ImVec4){1.0f, 0.302f, 0.302f, 1.0f}), 20);\n    }\n  }\n\n  android_voice_publish_hud(c.x - R, c.y - R, R * 2.0f);\n  android_team_draw_minimap(env, c.x - R, c.y - R, R * 2.0f);\n  android_team_set_chat_centre(usrs->hud_chat_x * W, usrs->hud_chat_y * H);\n\n  /* ---- leaderboard ---- */\n  if (!gdata->data.gotlb) {\n    original_lb_fade = 0.0f;\n    return;\n  }\n  float vfr = gdata->data.vfr;\n  if (!(vfr > 0.0f) || vfr > 4.0f) vfr = 1.0f;\n  original_lb_fade += 0.01f * vfr;\n  if (original_lb_fade > 1.0f) original_lb_fade = 1.0f;\n  float wdxo = roundf(0.057f * (W < H ? W : H) / u);\n  float lx = portrait ? W - (16.0f + 241.0f) * u : W - (16.0f + 241.0f + wdxo) * u;\n  float ly = notch;\n  float size = 11.0f * u;\n  int row_y = 0;\n  for (int row = 0; row < NUM_LEADERBOARD_ENTRIES; ++row) {\n    int score = gdata->data.lb.entries[row].score;\n    if (score <= 0 && !gdata->data.lb.entries[row].nickname[0]) continue;\n    bool mine = gdata->data.lb_pos == row + 1;\n    float k2 = mine ? 1.0f : 0.9f * (0.2f + 0.8f * powf(1.0f - (row + 1) / 10.0f, 0.66f));\n    float alpha = k2 * original_lb_fade;\n    int cv = gdata->data.lb.entries[row].cv;\n    if (cv < 0 || cv >= NUM_COLOR_GROUPS) cv = 0;\n    vec3s colour = gdata->cg_colors[cv];\n    float y = ly + (5.0f + 14.0f * row_y) * u;\n    char rank[8];\n    snprintf(rank, sizeof(rank), "#%d", row + 1);\n    original_text(draw, bold, size, (ImVec2){lx, y}, colour, alpha, rank);\n    const char* name = gdata->data.lb.entries[row].nickname;\n    if (name[0]) {\n      char fitted[MAX_NICKNAME_LEN + 8];\n      snprintf(fitted, sizeof(fitted), "%s", name);\n      int length = (int)strlen(fitted);\n      while (length > 1 && original_text_size(bold, size, fitted).x > 165.0f * u)\n        fitted[--length] = 0;\n      original_text(draw, bold, size, (ImVec2){lx + 28.0f * u, y}, colour, alpha, fitted);\n    }\n    char points[16];\n    snprintf(points, sizeof(points), "%d", score);\n    float pw = original_text_size(bold, size, points).x;\n    original_text(draw, bold, size, (ImVec2){lx + 241.0f * u - pw, y}, colour, alpha, points);\n    ++row_y;\n  }\n}\n\nvoid ui_overlay(tenv* env) {\n  tuser_data* usr = env->usr;'), ('    leaderboard_hit[2] = leaderboard_hit[3] = 0.0f;\n    if (gdata->data.gotlb) {', "    leaderboard_hit[2] = leaderboard_hit[3] = 0.0f;\n    /* Near Original: slither's own map and board instead (draw_original_hud). */\n    bool original_hud = android_home_near_original();\n    if (gdata->data.gotlb && !original_hud) {"), ('    /* Not in the background-size editor: only the map and the board there. */\n    if (!ai_mode_editor_bare()) {\n      const char* labels[] = {"SCORE", "KILLS", "RANK", "TIME", "PING", "FPS"};', '    /* Not in the background-size editor: only the map and the board there.\n       Not in Near Original either: the original has no stats. */\n    if (!ai_mode_editor_bare() && !original_hud) {\n      const char* labels[] = {"SCORE", "KILLS", "RANK", "TIME", "PING", "FPS"};'), ('    // The fullscreen gameplay window can inherit a large layout padding from\n    // the menu theme.', '    if (original_hud) {\n      draw_original_hud(env, draw);\n    } else {\n    // The fullscreen gameplay window can inherit a large layout padding from\n    // the menu theme.'), ('                               bearing_text, NULL,\n                               0, NULL);\n', '                               bearing_text, NULL,\n                               0, NULL);\n    }\n')])]
for _relative, _pairs in NEAR_ORIGINAL_PAIRS:
    _target = OUTPUT / _relative
    _text = _target.read_text(encoding="utf-8")
    _nl = "\r\n" if "\r\n" in _text else "\n"
    for _old, _new in _pairs:
        _old, _new = _old.replace("\n", _nl), _new.replace("\n", _nl)
        if _text.count(_old) != 1:
            raise SystemExit(f"near original: anchor missing in {_relative}: {_old[:60]!r}")
        _text = _text.replace(_old, _new, 1)
    _target.write_text(_text, encoding="utf-8")
for _font in ("nunito_bold.ttf", "nunito_black.ttf"):
    _source = ROOT / "Resources" / "Nunito" / _font
    if not _source.exists():
        raise SystemExit(f"near original: Resources/Nunito/{_font} is missing")
    shutil.copyfile(_source, OUTPUT / "app/res/fonts" / _font)
print("Near Original applied")

# Wyrm's own HUD, readable on any floor (OM, 2026-10-02): the ink halo on
# the leaderboard (snake colours, no dot), a floor-tinted ImGui minimap, and
# halos on the controls, zoom bar and on-screen keys. Same C as Wyrm Android.
WYRM_HUD_OVERLAY_PAIRS = [('void ui_overlay(tenv* env) {\n  tuser_data* usr = env->usr;\n  tcontext* ctx = env->ctx;\n', '/* ---- Wyrm\'s own HUD, readable on any floor (OM, 2026-10-02) ----\n * The original reads on every floor through contrast, not colour: an outline\n * and a shadow around every glyph. Wyrm does the same in its own hand: a soft\n * ink halo (a tight outline and a wide, low shadow in deep ink, never pure\n * black), each snake\'s own colour lifted until it reads, a slate plate under\n * the board only on light floors, and a minimap tinted by the floor at one\n * fixed darkness. Draw-only: nothing here touches input or the arena.\n */\n\n/* Each floor\'s mean colour (the same images, measured offline). */\nstatic const struct {\n  const char* id;\n  unsigned char r, g, b;\n} WYRM_FLOOR_MEAN[] = {\n    {"wyrm", 21, 27, 37},          {"classic", 26, 35, 47},\n    {"bgee2", 11, 24, 37},         {"asanoha", 109, 44, 52},\n    {"seigaiha", 99, 151, 194},    {"graygrid", 168, 168, 168},\n    {"rizz", 109, 83, 121},        {"usastar", 20, 38, 86},\n    {"circuits", 44, 39, 80},      {"circuits2", 49, 44, 108},\n    {"hexice", 81, 128, 165},      {"hexb", 36, 49, 96},\n    {"hearts", 234, 126, 151},     {"leaves", 175, 104, 68},\n    {"paint", 192, 146, 133},      {"snakey", 127, 144, 94},\n    {"stainedglass", 145, 96, 101}, {"kitties", 207, 127, 212},\n    {"bluecube", 89, 108, 235},    {"purplecube", 160, 53, 214},\n    {"redcube", 223, 80, 72},      {"wyrm_midnight", 12, 22, 39},\n    {"wyrm_carbon", 25, 28, 33},   {"wyrm_abyss", 8, 28, 34},\n    {"wyrm_nebula", 8, 7, 17},     {"wyrm_dotgrid", 16, 18, 21},\n    {"wyrm_contours", 15, 24, 29}, {"wyrm_scales", 17, 29, 23},\n};\n\n/* Deep ink for every halo: Wyrm\'s black with a little blue, never #000. */\nstatic const ImVec4 WYRM_HALO = {0.035f, 0.040f, 0.055f, 1.0f};\n\nstatic float wyrm_luma(vec3s c) {\n  return 0.2126f * c.x + 0.7152f * c.y + 0.0722f * c.z;\n}\n\n/* The floor really under the HUD (its mean colour), or false when none shows\n   (None, Black, or a mode that hides the floor). */\nstatic bool wyrm_floor_mean(tenv* env, vec3s* out) {\n  tuser_data* usr = env->usr;\n  if (usr->r->global.bg_opacity <= 0.0f || usr->r->global.bg_color[0] < 0.5f)\n    return false;\n  const char* id = BACKGROUNDS[background_clamp(usr->usrs.arena_background)].id;\n  int count = (int)(sizeof(WYRM_FLOOR_MEAN) / sizeof(WYRM_FLOOR_MEAN[0]));\n  for (int i = 0; i < count; ++i)\n    if (strcmp(WYRM_FLOOR_MEAN[i].id, id) == 0) {\n      *out = (vec3s){{WYRM_FLOOR_MEAN[i].r / 255.0f, WYRM_FLOOR_MEAN[i].g / 255.0f,\n                      WYRM_FLOOR_MEAN[i].b / 255.0f}};\n      return true;\n    }\n  return false;\n}\n\n/* A light floor (mean luma 0.30 or more) gets the slate plate. */\nstatic bool wyrm_floor_light(tenv* env) {\n  vec3s mean;\n  return wyrm_floor_mean(env, &mean) && wyrm_luma(mean) >= 0.30f;\n}\n\n/* A snake\'s colour, lifted toward white until it reads over the halo. */\nstatic ImU32 wyrm_snake_ink(vec3s c, float alpha) {\n  float l = wyrm_luma(c);\n  const float target = 0.62f;\n  if (l < target) {\n    float t = (target - l) / (1.0f - l + 0.0001f);\n    c.x += (1.0f - c.x) * t;\n    c.y += (1.0f - c.y) * t;\n    c.z += (1.0f - c.z) * t;\n  }\n  return igColorConvertFloat4ToU32((ImVec4){c.x, c.y, c.z, alpha});\n}\n\n/* Text in Wyrm\'s ink halo: a wide, low shadow and a tight outline. */\nstatic void wyrm_halo_text(ImDrawList* draw, ImFont* font, float size,\n                           ImVec2 pos, ImU32 colour, float alpha,\n                           const char* text) {\n  if (alpha <= 0.004f || !text || !text[0]) return;\n  float soft = size * 0.16f;\n  if (soft < 2.0f) soft = 2.0f;\n  float tight = size * 0.07f;\n  if (tight < 1.0f) tight = 1.0f;\n  ImU32 shadow = igColorConvertFloat4ToU32(\n      (ImVec4){WYRM_HALO.x, WYRM_HALO.y, WYRM_HALO.z, alpha * 0.10f});\n  for (int i = 0; i < 8; ++i) {\n    float a = 6.2831853f * (i + 0.5f) / 8.0f;\n    ImDrawList_AddText_FontPtr(\n        draw, font, size,\n        (ImVec2){pos.x + cosf(a) * soft, pos.y + sinf(a) * soft + soft * 0.35f},\n        shadow, text, NULL, 0, NULL);\n  }\n  /* The outline stamps overlap about two deep. */\n  float stamp = 1.0f - sqrtf(1.0f - 0.72f * alpha);\n  ImU32 ink = igColorConvertFloat4ToU32(\n      (ImVec4){WYRM_HALO.x, WYRM_HALO.y, WYRM_HALO.z, stamp});\n  for (int i = 0; i < 8; ++i) {\n    float a = 6.2831853f * i / 8.0f;\n    ImDrawList_AddText_FontPtr(\n        draw, font, size,\n        (ImVec2){pos.x + cosf(a) * tight, pos.y + sinf(a) * tight}, ink, text,\n        NULL, 0, NULL);\n  }\n  ImDrawList_AddText_FontPtr(draw, font, size, pos, colour, text, NULL, 0, NULL);\n}\n\n/* A name in the halo, shortened with "..." until it fits. */\nstatic void wyrm_halo_fitted(ImDrawList* draw, ImFont* font, ImVec2 pos,\n                             ImU32 colour, float alpha, const char* text,\n                             float max_width) {\n  if (measure(font, text) <= max_width) {\n    wyrm_halo_text(draw, font, font->LegacySize, pos, colour, alpha, text);\n    return;\n  }\n  char shortened[MAX_NICKNAME_LEN + 8];\n  int length = (int)strlen(text);\n  if (length > (int)sizeof(shortened) - 5) length = (int)sizeof(shortened) - 5;\n  while (length > 1) {\n    snprintf(shortened, sizeof(shortened), "%.*s...", --length, text);\n    if (measure(font, shortened) <= max_width) break;\n  }\n  wyrm_halo_text(draw, font, font->LegacySize, pos, colour, alpha, shortened);\n}\n\n/*\n * Wyrm\'s minimap, drawn here instead of the old glass shader (which was nearly\n * clear and lost on light floors). A disc tinted by the floor at one fixed\n * darkness, a faint compass cross and middle ring, the arena\'s cells in paper\n * white (eased, as before), a soft shadow, and you as a Wyrm-green chevron\n * pointing where your snake goes. The world circle maps to 0.9 of the radius,\n * as before (the death dot and the voice/team marks use the same frame).\n */\nstatic void wyrm_draw_minimap(tenv* env, ImDrawList* draw, float left,\n                              float top, float diameter) {\n  game_data* gdata = &env->usr->gdata;\n  float R = diameter * 0.5f;\n  ImVec2 c = {left + R, top + R};\n  original_disc_shadow(draw, c, R + 1.5f, 2.0f, 5.0f, 0.30f);\n\n  vec3s slate = {{0.085f, 0.095f, 0.120f}};\n  vec3s base = slate;\n  vec3s mean;\n  if (wyrm_floor_mean(env, &mean)) {\n    float l = wyrm_luma(mean);\n    float s = l > 0.001f ? 0.15f / l : 1.0f;\n    vec3s tint = {{mean.x * s > 1.0f ? 1.0f : mean.x * s,\n                   mean.y * s > 1.0f ? 1.0f : mean.y * s,\n                   mean.z * s > 1.0f ? 1.0f : mean.z * s}};\n    base.x = slate.x + (tint.x - slate.x) * 0.6f;\n    base.y = slate.y + (tint.y - slate.y) * 0.6f;\n    base.z = slate.z + (tint.z - slate.z) * 0.6f;\n  }\n  ImDrawList_AddCircleFilled(draw, c, R,\n                             igColorConvertFloat4ToU32((ImVec4){base.x, base.y, base.z, 0.86f}),\n                             64);\n  ImU32 faint = igColorConvertFloat4ToU32((ImVec4){1, 1, 1, 0.07f});\n  ImDrawList_AddLine(draw, (ImVec2){c.x - R * 0.92f, c.y}, (ImVec2){c.x + R * 0.92f, c.y}, faint, 1.0f);\n  ImDrawList_AddLine(draw, (ImVec2){c.x, c.y - R * 0.92f}, (ImVec2){c.x, c.y + R * 0.92f}, faint, 1.0f);\n  ImDrawList_AddCircle(draw, c, R * 0.45f, faint, 48, 1.0f);\n\n  /* The cells: eased values in six steps, one rect per run of a step. */\n  int mmsz = gdata->data.mmsz;\n  if (mmsz > MAX_MINIMAP_SIZE) mmsz = MAX_MINIMAP_SIZE;\n  if (mmsz > 0) {\n    float span = R * 0.9f * 2.0f;\n    float cell = span / mmsz;\n    float ox = c.x - R * 0.9f;\n    float oy = c.y - R * 0.9f;\n    for (int y = 0; y < mmsz; ++y) {\n      const float* row = gdata->data.mm_data_follow + y * MAX_MINIMAP_SIZE;\n      int x = 0;\n      while (x < mmsz) {\n        int level = (int)(row[x] * 6.0f + 0.5f);\n        if (level <= 0) { ++x; continue; }\n        if (level > 6) level = 6;\n        int start = x;\n        while (x < mmsz) {\n          int next = (int)(row[x] * 6.0f + 0.5f);\n          if (next > 6) next = 6;\n          if (next != level) break;\n          ++x;\n        }\n        ImDrawList_AddRectFilled(\n            draw, (ImVec2){ox + start * cell, oy + y * cell},\n            (ImVec2){ox + x * cell, oy + (y + 1) * cell},\n            igColorConvertFloat4ToU32((ImVec4){1, 1, 1, 0.62f * level / 6.0f}), 0, 0);\n      }\n    }\n  }\n\n  /* You: a chevron along the drawn head\'s angle, in the green of the mark. */\n  float world = gdata->data.flux_grd;\n  int count = tdarray_length(gdata->data.snakes);\n  if (world > 1.0f && count) {\n    snake* me = gdata->data.snakes + (count - 1);\n    if (me->local_player && gdata->data.snake_id == me->id) {\n      float nx = (me->xx + me->fx - gdata->data.grd) / world;\n      float ny = (me->yy + me->fy - gdata->data.grd) / world;\n      float reach = sqrtf(nx * nx + ny * ny);\n      if (reach > 1.0f) { nx /= reach; ny /= reach; }\n      ImVec2 p = {c.x + nx * R * 0.9f, c.y + ny * R * 0.9f};\n      float dx = cosf(me->ehang), dy = sinf(me->ehang);\n      float s = R * 0.085f;\n      if (s < 4.0f) s = 4.0f;\n      for (int pass = 0; pass < 2; ++pass) {\n        float k = pass == 0 ? s * 1.45f : s;\n        ImVec2 tip = {p.x + dx * k * 1.25f, p.y + dy * k * 1.25f};\n        ImVec2 l = {p.x - dx * k * 0.8f - dy * k * 0.75f, p.y - dy * k * 0.8f + dx * k * 0.75f};\n        ImVec2 r = {p.x - dx * k * 0.8f + dy * k * 0.75f, p.y - dy * k * 0.8f - dx * k * 0.75f};\n        ImVec2 notch = {p.x - dx * k * 0.35f, p.y - dy * k * 0.35f};\n        ImU32 col = pass == 0\n                        ? igColorConvertFloat4ToU32((ImVec4){WYRM_HALO.x, WYRM_HALO.y, WYRM_HALO.z, 0.78f})\n                        : igColorConvertFloat4ToU32((ImVec4){0.247f, 0.933f, 0.588f, 1.0f});\n        ImDrawList_AddTriangleFilled(draw, tip, l, notch, col);\n        ImDrawList_AddTriangleFilled(draw, tip, notch, r, col);\n      }\n    }\n  }\n}\n\nvoid ui_overlay(tenv* env) {\n  tuser_data* usr = env->usr;\n  tcontext* ctx = env->ctx;\n'), ('      float row_height = score_size.y + 7.0f;\n      float dot = 5.0f;\n      float board_width = GLM_MAX(\n          position_size.x, GLM_MAX(hint_size.x,\n                                   rank_size.x + 10.0f + dot * 2 + 8.0f +\n                                       name_size.x + 12.0f + score_size.x));', '      float row_height = score_size.y + 7.0f;\n      float board_width = GLM_MAX(\n          position_size.x, GLM_MAX(hint_size.x,\n                                   rank_size.x + 10.0f + name_size.x + 12.0f +\n                                       score_size.x));'), ('      ImVec2 board_max = {board_min.x + board_width, board_min.y};\n\n      ImDrawList_AddText_FontPtr(draw, label_font, label_font->LegacySize,\n                                 board_min,\n                                 arena_theme_overlay_text(0.92f), "Leaderboard",\n                                 NULL, 0, NULL);', '      ImVec2 board_max = {board_min.x + board_width, board_min.y};\n\n      /* A slate plate only where the floor is light (OM, 2026-10-02). */\n      if (wyrm_floor_light(env)) {\n        ImVec2 plate_min = {board_min.x - 12.0f, board_min.y - 10.0f};\n        ImVec2 plate_max = {board_max.x + 12.0f, board_min.y + board_height + 10.0f};\n        ImDrawList_AddRectFilled(draw, (ImVec2){plate_min.x, plate_min.y + 3.0f},\n                                 (ImVec2){plate_max.x, plate_max.y + 3.0f},\n                                 hud_colour(0, 0, 0, 0.14f), HUD_PANEL_ROUNDING, 0);\n        ImDrawList_AddRectFilled(draw, plate_min, plate_max,\n                                 hud_colour(WYRM_HALO.x + 0.02f, WYRM_HALO.y + 0.025f,\n                                            WYRM_HALO.z + 0.03f, 0.50f),\n                                 HUD_PANEL_ROUNDING, 0);\n        ImDrawList_AddRect(draw, plate_min, plate_max, hud_colour(1, 1, 1, 0.10f),\n                           HUD_PANEL_ROUNDING, 0, 1.0f);\n      }\n\n      wyrm_halo_text(draw, label_font, label_font->LegacySize, board_min,\n                     arena_theme_overlay_text(0.92f), 0.92f, "Leaderboard");'), ('        char rank_text[8];\n        snprintf(rank_text, sizeof(rank_text), "%d", row + 1);\n        ImVec2 measured;\n        igPushFont(rank_font, rank_font->LegacySize);\n        igCalcTextSize(&measured, rank_text, NULL, false, -1);\n        igPopFont();\n        ImDrawList_AddText_FontPtr(\n            draw, rank_font, rank_font->LegacySize,\n            (ImVec2){board_min.x + rank_size.x - measured.x, row_y + 2.0f},\n            arena_theme_overlay_text(mine ? 1.0f : 0.78f), rank_text, NULL, 0,\n            NULL);\n\n        /* The one place colour is still worth spending: whose snake this is. */\n        vec3s* snake_colour = gdata->cg_colors + gdata->data.lb.entries[row].cv;\n        ImDrawList_AddCircleFilled(\n            draw,\n            (ImVec2){board_min.x + rank_size.x + 10.0f + dot,\n                     row_y + row_height * 0.42f},\n            dot,\n            igColorConvertFloat4ToU32((ImVec4){snake_colour->x, snake_colour->y,\n                                               snake_colour->z, alpha}),\n            16);\n\n        char score_text_row[16];\n        snprintf(score_text_row, sizeof(score_text_row), "%d",\n                 gdata->data.lb.entries[row].score);\n        float score_width = measure(score_font, score_text_row);\n\n        /* The name gets whatever is left after the score has taken its width,\n           and is shortened to fit rather than allowed to run over it. */\n        float name_x = board_min.x + rank_size.x + 10.0f + dot * 2 + 8.0f;\n        draw_fitted_text(draw, name_font, (ImVec2){name_x, row_y + 3.0f},\n                         leaderboard_name_colour(row, alpha),\n                         gdata->data.lb.entries[row].nickname,\n                         board_max.x - score_width - 10.0f - name_x);\n\n        measured.x = score_width;\n        ImDrawList_AddText_FontPtr(draw, score_font, score_font->LegacySize,\n                                   (ImVec2){board_max.x - measured.x, row_y},\n                                   arena_theme_overlay_text(alpha), score_text_row,\n                                   NULL, 0, NULL);', '        /* Your own row sits on a soft ink pill. */\n        if (mine)\n          ImDrawList_AddRectFilled(\n              draw, (ImVec2){board_min.x - 6.0f, row_y - 1.0f},\n              (ImVec2){board_max.x + 6.0f, row_y + row_height - 1.0f},\n              hud_colour(WYRM_HALO.x, WYRM_HALO.y, WYRM_HALO.z, 0.34f),\n              row_height * 0.5f, 0);\n\n        char rank_text[8];\n        snprintf(rank_text, sizeof(rank_text), "%d", row + 1);\n        ImVec2 measured;\n        igPushFont(rank_font, rank_font->LegacySize);\n        igCalcTextSize(&measured, rank_text, NULL, false, -1);\n        igPopFont();\n        wyrm_halo_text(draw, rank_font, rank_font->LegacySize,\n                       (ImVec2){board_min.x + rank_size.x - measured.x, row_y + 2.0f},\n                       arena_theme_overlay_text(mine ? 1.0f : 0.78f),\n                       mine ? 1.0f : 0.78f, rank_text);\n\n        /* Whose snake this is: the name and the score in its own colour\n           (OM, 2026-10-02: no dot), lifted until it reads. */\n        int lb_cv = gdata->data.lb.entries[row].cv;\n        if (lb_cv < 0 || lb_cv >= NUM_COLOR_GROUPS) lb_cv = 0;\n        ImU32 snake_ink = wyrm_snake_ink(gdata->cg_colors[lb_cv], alpha);\n\n        char score_text_row[16];\n        snprintf(score_text_row, sizeof(score_text_row), "%d",\n                 gdata->data.lb.entries[row].score);\n        float score_width = measure(score_font, score_text_row);\n\n        /* The name gets whatever is left after the score has taken its width,\n           and is shortened to fit rather than allowed to run over it. */\n        float name_x = board_min.x + rank_size.x + 10.0f;\n        wyrm_halo_fitted(draw, name_font, (ImVec2){name_x, row_y + 3.0f},\n                         snake_ink, alpha, gdata->data.lb.entries[row].nickname,\n                         board_max.x - score_width - 10.0f - name_x);\n\n        measured.x = score_width;\n        wyrm_halo_text(draw, score_font, score_font->LegacySize,\n                       (ImVec2){board_max.x - measured.x, row_y}, snake_ink,\n                       alpha, score_text_row);'), ('      float footer_y = rows_bottom + 8.0f;\n      ImDrawList_AddText_FontPtr(draw, label_font, label_font->LegacySize,\n                                 (ImVec2){board_min.x, footer_y},\n                                 arena_theme_overlay_text(0.92f), "Your position",\n                                 NULL, 0, NULL);\n      float rank_width = measure(score_font, rank_text);\n      ImDrawList_AddText_FontPtr(draw, score_font, score_font->LegacySize,\n                                 (ImVec2){board_max.x - rank_width, footer_y},\n                                 arena_theme_overlay_text(1.0f), rank_text, NULL, 0,\n                                 NULL);', '      float footer_y = rows_bottom + 8.0f;\n      wyrm_halo_text(draw, label_font, label_font->LegacySize,\n                     (ImVec2){board_min.x, footer_y},\n                     arena_theme_overlay_text(0.92f), 0.92f, "Your position");\n      float rank_width = measure(score_font, rank_text);\n      wyrm_halo_text(draw, score_font, score_font->LegacySize,\n                     (ImVec2){board_max.x - rank_width, footer_y},\n                     arena_theme_overlay_text(1.0f), 1.0f, rank_text);'), ('      ImDrawList_AddText_FontPtr(draw, label_font, label_font->LegacySize,\n                                 (ImVec2){board_min.x, footer_y},\n                                 arena_theme_overlay_text(0.66f), hint, NULL, 0,\n                                 NULL);', '      wyrm_halo_text(draw, label_font, label_font->LegacySize,\n                     (ImVec2){board_min.x, footer_y},\n                     arena_theme_overlay_text(0.66f), 0.66f, hint);'), ('    usr->r->global.minimap_circ[0] = minimap_left;\n    usr->r->global.minimap_circ[1] = minimap_top;\n    usr->r->global.minimap_opacity = 1;\n\n    // minimap_circ.z is already the rendered quad width/diameter.\n    android_voice_publish_hud(minimap_left, minimap_top, minimap_diameter);', "    usr->r->global.minimap_circ[0] = minimap_left;\n    usr->r->global.minimap_circ[1] = minimap_top;\n    /* Wyrm's own disc (wyrm_draw_minimap); the glass shader stays off. */\n    wyrm_draw_minimap(env, draw, minimap_left, minimap_top, minimap_diameter);\n\n    // minimap_circ.z is already the rendered quad width/diameter.\n    android_voice_publish_hud(minimap_left, minimap_top, minimap_diameter);"), ('    /* The map itself is drawn by a shader underneath; this is the paper frame\n       it sits in. Only the rim and the shadow are drawn here — a filled disc\n       would be painted straight over the map, since the interface layer is\n       composited last. */', "    /* The paper rim around Wyrm's disc (the shadow is the disc's own). */"), ('    ImDrawList_AddCircle(draw, (ImVec2){map_centre.x, map_centre.y + 2.0f},\n                         map_radius + 3.0f, hud_colour(0, 0, 0, 0.16f), 64,\n                         6.0f);\n    ImDrawList_AddCircle(draw, map_centre, map_radius + 1.5f,', '    ImDrawList_AddCircle(draw, map_centre, map_radius + 1.5f,')]
WYRM_HUD_CONTROLS_PAIRS = [('static void draw_paper_disc(ImDrawList* dl, float cx, float cy, float radius,\n                            float alpha, bool active) {\n', "static void draw_paper_disc(ImDrawList* dl, float cx, float cy, float radius,\n                            float alpha, bool active) {\n  /* Wyrm's ink halo (OM, 2026-10-02): the edge holds on a white floor too. */\n  for (int i = 0; i < 4; ++i)\n    ImDrawList_AddCircle(dl, (ImVec2){cx, cy}, radius + 2.0f + i * 2.5f,\n                         color_u32(0.035f, 0.040f, 0.055f, alpha * (0.16f - i * 0.035f)),\n                         48, 2.5f);\n  if (active)\n    ImDrawList_AddCircle(dl, (ImVec2){cx, cy}, radius + 3.5f,\n                         color_u32(0.247f, 0.933f, 0.588f, alpha * 0.55f), 48, 3.0f);\n"), ('  ImDrawList_AddRectFilled(dl, (ImVec2){track_min.x, track_min.y + half * 0.18f},\n                           (ImVec2){track_max.x, track_max.y + half * 0.18f},\n                           color_u32(0, 0, 0, alpha * 0.16f), half, 0);', "  /* Wyrm's ink halo around the bar (OM, 2026-10-02). */\n  for (int i = 0; i < 4; ++i) {\n    float grow = 2.0f + i * 2.5f;\n    ImDrawList_AddRect(dl, (ImVec2){track_min.x - grow, track_min.y - grow},\n                       (ImVec2){track_max.x + grow, track_max.y + grow},\n                       color_u32(0.035f, 0.040f, 0.055f, alpha * (0.16f - i * 0.035f)),\n                       half + grow, 0, 2.5f);\n  }\n  ImDrawList_AddRectFilled(dl, (ImVec2){track_min.x, track_min.y + half * 0.18f},\n                           (ImVec2){track_max.x, track_max.y + half * 0.18f},\n                           color_u32(0, 0, 0, alpha * 0.16f), half, 0);")]
WYRM_HUD_HOTKEYS_PAIRS = [('    /* Paper paint inside the exact same rectangle used by hit_action(). Input,\n       mode and placement are deliberately not part of this draw function. */\n', "    /* Wyrm's ink halo (OM, 2026-10-02): the key's edge holds on a white floor\n       too; a pressed or lit key also gets a green ring. */\n    for (int i = 0; i < 4; ++i) {\n      float grow = 2.0f + i * 2.5f;\n      ImDrawList_AddRect(draw, (ImVec2){min.x - grow, min.y - grow},\n                         (ImVec2){max.x + grow, max.y + grow},\n                         color(0.035f, 0.040f, 0.055f, alpha * (0.16f - i * 0.035f)),\n                         corner + grow, 0, 2.5f);\n    }\n    if (active || pressed)\n      ImDrawList_AddRect(draw, (ImVec2){min.x - 3.5f, min.y - 3.5f},\n                         (ImVec2){max.x + 3.5f, max.y + 3.5f},\n                         color(0.247f, 0.933f, 0.588f, alpha * 0.55f),\n                         corner + 3.5f, 0, 3.0f);\n    /* Paper paint inside the exact same rectangle used by hit_action(). Input,\n       mode and placement are deliberately not part of this draw function. */\n")]
_arrow_patch("app/src/game/ui_overlay.c", WYRM_HUD_OVERLAY_PAIRS)
_arrow_patch("app/src/mobile/mobile_controls.c", WYRM_HUD_CONTROLS_PAIRS)
_arrow_patch("app/src/mobile/mobile_hotkeys.c", WYRM_HUD_HOTKEYS_PAIRS)
print("Wyrm HUD: ink halo, snake-coloured board, floor-tinted minimap")

# Play feel (OM, 2026-10-05): slither's own arrow motion, look ahead, the
# original arrow's shadow and the original arrow in Wyrm mode, and the spring
# zoom bar. The same C as Wyrm Android's mobile/mobile_controls.c/.h and
# game/redraw.c, applied last. Revert: delete this block.
PLAY_FEEL_PAIRS = {
  'app/src/mobile/mobile_controls.c': [
    (r'''static bool original_joystick_right(tenv* env) {''',
     r'''/*
 * Play feel (OM, 2026-10-05), set by the app (Settings > Controls) through
 * mobile_controls_set_play_feel:
 *  - original_arrow: slither's own arrow motion, number for number (Main.as).
 *    Near Original always moves like this; Wyrm's arrow does when
 *    "Customise arrow movement" is off.
 *  - look_ahead: slither's look ahead (Main.as `look_ahead`), both modes.
 *  - zoom_spring: the zoom bar as a spring: the knob rests in the middle,
 *    toward + zooms in, toward - zooms out, and it springs back on release.
 * Plain ints: written from the app's thread, read once a frame here.
 */
static volatile int feel_original_arrow = 0;
static volatile int feel_look_ahead = 0;
static volatile int feel_zoom_spring = 0;

void mobile_controls_set_play_feel(bool original_arrow, bool look_ahead,
                                   int zoom_style) {
  feel_original_arrow = original_arrow ? 1 : 0;
  feel_look_ahead = look_ahead ? 1 : 0;
  feel_zoom_spring = zoom_style == 1 ? 1 : 0;
}

/* Whether the arrow moves exactly as slither's does. */
static bool arrow_original_motion(void) {
  return android_home_near_original() || feel_original_arrow != 0;
}

/* The spring zoom knob: -1 (all the way to -) .. 1 (all the way to +). */
static float zoom_spring_t = 0.0f;

/* Look ahead (Main.as `view_lav`, `lav_d`), in the original's units. */
static float look_lav = 0.0f;
static float look_lav_d = 75.0f;

/* The player's own snake while alive, or NULL. */
static snake* feel_own_snake(tenv* env) {
  game_data* gdata = &env->usr->gdata;
  int count = tdarray_length(gdata->data.snakes);
  if (count <= 0) return NULL;
  snake* own = gdata->data.snakes + (count - 1);
  return own->local_player ? own : NULL;
}

/*
 * Look ahead, once a frame (Main.as 12891-12950). Sideways the camera moves
 * up or down toward where the snake is heading (sin of its eased angle,
 * squared with its sign), upright left or right (cos); 75 units ahead, 125
 * while boosting, eased by slither's own p005 / p01 tables and never more than
 * 160 a step. Off: no offset at all, and it starts from zero when turned on.
 */
void mobile_controls_look_ahead_step(tenv* env) {
  snake* own = feel_own_snake(env);
  if (!feel_look_ahead || !own) {
    look_lav = 0.0f;
    look_lav_d = 75.0f;
    return;
  }
  if (own->dead) return;
  game_data* gdata = &env->usr->gdata;
  float vfr = gdata->data.vfr;
  if (!(vfr > 0.0f)) vfr = 0.0f;
  int vfrb = gdata->data.vfrb;
  if (vfrb < 0) vfrb = 0;
  if (vfrb > 120) vfrb = 120;
  bool upright = env->wnd->size[1] > env->wnd->size[0];
  float s = upright ? cosf(own->eang) : sinf(own->eang);
  s = s < 0.0f ? -(s * s) : s * s;
  bool wmd = gdata->data.wmd || mobile_controls_boost_down(env);
  if (wmd) {
    if (look_lav_d != 125.0f) {
      look_lav_d += vfr * 0.5f;
      if (look_lav_d >= 125.0f) look_lav_d = 125.0f;
    }
  } else if (look_lav_d != 75.0f) {
    look_lav_d -= vfr * 0.25f;
    if (look_lav_d <= 75.0f) look_lav_d = 75.0f;
  }
  float step = s * look_lav_d - look_lav;
  if (step < -160.0f) step = -160.0f;
  if (step > 160.0f) step = 160.0f;
  float k = wmd ? 0.01f : 0.005f;
  look_lav += step * (1.0f - powf(1.0f - k, (float)vfrb));
}

/* Where the camera sits ahead of the snake, in screen pixels (the snake is
   drawn this far the other way from the middle). */
void mobile_controls_look_ahead_offset(tenv* env, float* x, float* y) {
  *x = 0.0f;
  *y = 0.0f;
  if (!feel_look_ahead) return;
  float px = look_lav * original_unit(env);
  if (env->wnd->size[1] > env->wnd->size[0])
    *x = px;
  else
    *y = px;
}

static bool original_joystick_right(tenv* env) {'''),
    (r'''static void set_zoom_from_touch(tenv* env, float x, float y) {
  mobile_control_settings* cfg = &env->usr->usrs.mobile_controls;
  float cx, cy, length, thickness;
  zoom_geometry(env, &cx, &cy, &length, &thickness);
''',
     r'''static void set_zoom_from_touch(tenv* env, float x, float y) {
  mobile_control_settings* cfg = &env->usr->usrs.mobile_controls;
  float cx, cy, length, thickness;
  zoom_geometry(env, &cx, &cy, &length, &thickness);
  if (feel_zoom_spring) {
    /* The spring bar (OM, 2026-10-05): the finger pulls the knob from the
       middle; + is right (sideways bar) or up (upright bar). */
    float pull = cfg->zoom_orientation == MOBILE_ZOOM_HORIZONTAL
                     ? (x - cx) / (length * 0.5f)
                     : (cy - y) / (length * 0.5f);
    zoom_spring_t = clampf(pull, -1.0f, 1.0f);
    return;
  }
'''),
    (r'''  /* Near Original: the original start distance (separation 1). */
  float separation = android_home_near_original() ? 1.0f : arrow->separation;
  float d = 58.0f * sc * gdata->data.gsc * separation;''',
     r'''  /* slither's own start distance (Main.as touch begin): 58 x snake.sc x its
     zoom for this length (dgsc = 0.35 + 0.35 / max(1, (sct + 16) / 36)) in its
     unit, with no floor (OM, 2026-10-05). */
  if (arrow_original_motion()) {
    int sct = count > 0 ? gdata->data.snakes[count - 1].sct : 2;
    float wanted = (sct + 16) / 36.0f;
    float dgsc = 0.35f + 0.35f / (wanted > 1.0f ? wanted : 1.0f);
    return 58.0f * sc * dgsc * original_unit(env);
  }
  float separation = arrow->separation;
  float d = 58.0f * sc * gdata->data.gsc * separation;'''),
    (r'''  int count = tdarray_length(gdata->data.snakes);
  float heading = count > 0 ? gdata->data.snakes[count - 1].ang : 0.0f;
  float d = arrow_seed_distance(env);''',
     r'''  int count = tdarray_length(gdata->data.snakes);
  float heading = count > 0 ? gdata->data.snakes[count - 1].ang : 0.0f;
  /* slither seeds along the last steering angle (`twang`), not the snake's. */
  if (arrow_original_motion() && state->aim_valid &&
      (state->joystick_axis[0] != 0.0f || state->joystick_axis[1] != 0.0f))
    heading = atan2f(state->joystick_axis[1], state->joystick_axis[0]);
  float d = arrow_seed_distance(env);'''),
    (r'''    /* Near Original: slither's own 0.6 catch-up (smoothness 0.4). */
    float smoothness = android_home_near_original() ? 0.4f : arrow->smoothness;
    float ease = clampf(1.0f - smoothness, 0.05f, 0.95f);
    ease = 1.0f - powf(1.0f - ease, vfr);''',
     r'''    /* The original motion eases 0.6 every frame, as Main.as does (not per
       unit of time); Wyrm's own uses the player's lag, frame-rate free. */
    float ease;
    if (arrow_original_motion()) {
      ease = 0.6f;
    } else {
      ease = clampf(1.0f - arrow->smoothness, 0.05f, 0.95f);
      ease = 1.0f - powf(1.0f - ease, vfr);
    }'''),
    (r'''    /* Near Original: the boost button's alpha (Main.as: 0.2 idle, up to 0.4''',
     r'''    /* The spring zoom bar: while pulled it zooms (gently near the middle,
       quickly at the ends); let go, it springs back to the middle. */
    if (feel_zoom_spring) {
      if (!state->zoom_down) {
        zoom_spring_t *= powf(0.72f, vfr);
        if (fabsf(zoom_spring_t) < 0.01f) zoom_spring_t = 0.0f;
      }
      if (fabsf(zoom_spring_t) > 0.04f) {
        float rate = 1.4f * zoom_spring_t * fabsf(zoom_spring_t);
        float* zoom = &env->usr->gdata.data.ms_zoom;
        *zoom *= expf(rate * vfr * 0.008f);
        *zoom = clampf(*zoom, MAX_ZOOM_OUT, MAX_ZOOM_IN);
      }
    } else {
      zoom_spring_t = 0.0f;
    }

    /* Near Original: the boost button's alpha (Main.as: 0.2 idle, up to 0.4'''),
    (r'''  /* Near Original: the release drift is in the original's unit. */
  float drift = 260.0f * (android_home_near_original() ? original_unit(env) : scale) *
                powf(state->arrow_dead, 2.5f);
  *ax = env->wnd->size[0] * 0.5f + state->arrow_draw[0] + *dx * drift;
  *ay = env->wnd->size[1] * 0.5f + state->arrow_draw[1] + *dy * drift;''',
     r'''  /* The original motion drifts 260 of the original's units. */
  float drift = 260.0f * (arrow_original_motion() ? original_unit(env) : scale) *
                powf(state->arrow_dead, 2.5f);
  /* Look ahead moves the camera, so the arrow keeps to the snake (Main.as:
     arrow_batch at -view_lav). */
  float lax, lay;
  mobile_controls_look_ahead_offset(env, &lax, &lay);
  *ax = env->wnd->size[0] * 0.5f - lax + state->arrow_draw[0] + *dx * drift;
  *ay = env->wnd->size[1] * 0.5f - lay + state->arrow_draw[1] + *dy * drift;'''),
    (r'''static void draw_arrow(tenv* env, ImDrawList* dl) {
  mobile_control_settings* cfg = &env->usr->usrs.mobile_controls;''',
     r'''static void draw_original_arrow(tenv* env, ImDrawList* dl);

static void draw_arrow(tenv* env, ImDrawList* dl) {
  mobile_control_settings* cfg = &env->usr->usrs.mobile_controls;'''),
    (r'''  mobile_arrow_shape shape = arrow_shape(env->usr->usrs.arrow_style);
  ImVec2 points[8];''',
     r'''  /* The Original style is slither's own arrow, drawn as Near Original draws
     it: outline, shadow, the snake's arrow colour, its size (OM, 2026-10-05).
     An image arrow (above) still wins. */
  if (env->usr->usrs.arrow_style == MOBILE_ARROW_ORIGINAL) {
    draw_original_arrow(env, dl);
    return;
  }
  mobile_arrow_shape shape = arrow_shape(env->usr->usrs.arrow_style);
  ImVec2 points[8];'''),
    (r'''  {
    const int bands = 8;
    const float sigma = 6.0f;
    float before = 0.0f;
    for (int j = bands; j >= 1; --j) {
      float x = (j - 0.5f) * (3.0f * sigma / bands);
      float want = alpha * 0.5f * erfcf(x / (sigma * 1.41421356f));
      float a = before >= 0.999f ? 0.0f : 1.0f - (1.0f - want) / (1.0f - before);
      if (a > 0.003f)
        ImDrawList_AddPolyline(dl, p, 7, color_u32(0, 0, 0, a), ImDrawFlags_Closed,
                               (9.0f + 2.0f * j * (3.0f * sigma / bands)) * s);
      if (want > before) before = want;
    }
  }''',
     r'''  /* OM, 2026-10-05: the shadow spread the arrow. slither draws it inside an
     84 px texture with the arrow 10 px in, so it reaches only about 11.5 px
     past the 9 px outline; and thick closed strokes grew mitre spikes at the
     head's corners. Now: nested fills of the outline pushed out by d along
     each corner's bisector (no mitre), widest first, the same erfc profile,
     never past 11.5 texture px, drawn as rings outside the path. */
  {
    const int bands = 6;
    const float sigma = 6.0f;
    const float reach = 11.5f;
    /* The outline's outside edge: 4.5 px out from the path. */
    float before = 0.0f;
    for (int j = bands; j >= 1; --j) {
      float x = (j - 0.5f) * (reach / bands);
      float want = alpha * 0.5f * erfcf(x / (sigma * 1.41421356f));
      float a = before >= 0.999f ? 0.0f : 1.0f - (1.0f - want) / (1.0f - before);
      if (a > 0.003f) {
        float d = 4.5f + j * (reach / bands);
        ImVec2 q[7];
        for (int i = 0; i < 7; ++i) {
          int prev = (i + 6) % 7, next = (i + 1) % 7;
          /* Outward normals of the two edges at this corner (the shape winds
             clockwise in screen space: x along, y across). */
          float e1x = shape_x[i] - shape_x[prev], e1y = shape_y[i] - shape_y[prev];
          float e2x = shape_x[next] - shape_x[i], e2y = shape_y[next] - shape_y[i];
          float l1 = sqrtf(e1x * e1x + e1y * e1y), l2 = sqrtf(e2x * e2x + e2y * e2y);
          float n1x = e1y / l1, n1y = -e1x / l1;
          float n2x = e2y / l2, n2y = -e2x / l2;
          float bx = n1x + n2x, by = n1y + n2y;
          float bl = sqrtf(bx * bx + by * by);
          if (bl < 0.0001f) { bx = n1x; by = n1y; bl = 1.0f; }
          float ox = shape_x[i] + bx / bl * d * shadow_side;
          float oy = shape_y[i] + by / bl * d * shadow_side;
          q[i] = (ImVec2){ax + dx * ox * s + px * oy * s, ay + dy * ox * s + py * oy * s};
        }
        /* A ring from the path out to q: nothing lands under the fill, which
           the arrow's own alpha would let show through. */
        ImU32 shade = color_u32(0, 0, 0, a);
        for (int i = 0; i < 7; ++i) {
          int next = (i + 1) % 7;
          ImDrawList_AddTriangleFilled(dl, p[i], p[next], q[next], shade);
          ImDrawList_AddTriangleFilled(dl, p[i], q[next], q[i], shade);
        }
      }
      if (want > before) before = want;
    }
  }'''),
    (r'''  static const float shape_x[] = {15.0f, 15.0f, 41.0f, 41.0f, 67.0f, 41.0f, 41.0f};
  static const float shape_y[] = {-10.88f, 10.88f, 7.68f, 25.6f, 0.0f, -25.6f, -7.68f};''',
     r'''  static const float shape_x[] = {15.0f, 15.0f, 41.0f, 41.0f, 67.0f, 41.0f, 41.0f};
  static const float shape_y[] = {-10.88f, 10.88f, 7.68f, 25.6f, 0.0f, -25.6f, -7.68f};
  /* (e.y, -e.x) of each edge points out of a counter-clockwise shape. */
  float shadow_area = 0.0f;
  for (int i = 0; i < 7; ++i) {
    int next = (i + 1) % 7;
    shadow_area += shape_x[i] * shape_y[next] - shape_x[next] * shape_y[i];
  }
  float shadow_side = shadow_area > 0.0f ? 1.0f : -1.0f;'''),
    (r'''  /* The run reads from the near end to the knob, whichever way the bar sits. */
  ImVec2 fill_min = track_min;
  ImVec2 fill_max = track_max;
  if (cfg->zoom_orientation == MOBILE_ZOOM_HORIZONTAL)
    fill_max.x = knob.x;
  else
    fill_min.y = knob.y;''',
     r'''  /* The spring bar (OM, 2026-10-05): the knob rests in the middle, the run
     reads from the middle to the knob, with - and + at the two ends. */
  if (feel_zoom_spring) {
    float half_len = length * 0.5f;
    if (cfg->zoom_orientation == MOBILE_ZOOM_HORIZONTAL)
      knob = (ImVec2){cx + zoom_spring_t * half_len, cy};
    else
      knob = (ImVec2){cx, cy - zoom_spring_t * half_len};
  }
  /* The run reads from the near end to the knob, whichever way the bar sits. */
  ImVec2 fill_min = track_min;
  ImVec2 fill_max = track_max;
  if (feel_zoom_spring) {
    if (cfg->zoom_orientation == MOBILE_ZOOM_HORIZONTAL) {
      fill_min.x = knob.x < cx ? knob.x : cx;
      fill_max.x = knob.x < cx ? cx : knob.x;
    } else {
      fill_min.y = knob.y < cy ? knob.y : cy;
      fill_max.y = knob.y < cy ? cy : knob.y;
    }
    float mark = half * 0.9f;
    ImU32 sign = arena_theme_colour(ARENA_THEME_INK, alpha * 0.9f);
    float inset = half * 2.2f;
    ImVec2 minus, plus;
    if (cfg->zoom_orientation == MOBILE_ZOOM_HORIZONTAL) {
      minus = (ImVec2){track_min.x + inset, cy};
      plus = (ImVec2){track_max.x - inset, cy};
    } else {
      minus = (ImVec2){cx, track_max.y - inset};
      plus = (ImVec2){cx, track_min.y + inset};
    }
    ImDrawList_AddLine(dl, (ImVec2){minus.x - mark, minus.y}, (ImVec2){minus.x + mark, minus.y}, sign, 2.5f);
    ImDrawList_AddLine(dl, (ImVec2){plus.x - mark, plus.y}, (ImVec2){plus.x + mark, plus.y}, sign, 2.5f);
    ImDrawList_AddLine(dl, (ImVec2){plus.x, plus.y - mark}, (ImVec2){plus.x, plus.y + mark}, sign, 2.5f);
  } else if (cfg->zoom_orientation == MOBILE_ZOOM_HORIZONTAL)
    fill_max.x = knob.x;
  else
    fill_min.y = knob.y;'''),
  ],
  'app/src/mobile/mobile_controls.h': [
    (r'''bool mobile_controls_get_arrow_position(tenv* env, float* x, float* y);
''',
     r'''bool mobile_controls_get_arrow_position(tenv* env, float* x, float* y);

/* Play feel (OM, 2026-10-05), from the app: slither's own arrow motion (Wyrm
   mode; Near Original always), look ahead (both modes), and the zoom bar's
   style (0 the slider, 1 the spring). */
void mobile_controls_set_play_feel(bool original_arrow, bool look_ahead,
                                   int zoom_style);
/* Look ahead: step it once a frame (redraw), then read the camera's offset
   in screen pixels (the snake is drawn this far the other way). */
void mobile_controls_look_ahead_step(tenv* env);
void mobile_controls_look_ahead_offset(tenv* env, float* x, float* y);
'''),
  ],
  'app/src/game/redraw.c': [
    (r'''#include "tags.h"
''',
     r'''#include "tags.h"
#include "../mobile/mobile_controls.h"
'''),
    (r'''    if (gdata->data.follow_view && snakes_len > 0) {
      snake* me = gdata->data.snakes + (snakes_len - 1);
      gdata->data.view_xx = me->xx + me->fx + gdata->data.fvx;
      gdata->data.view_yy = me->yy + me->fy + gdata->data.fvy;
    }''',
     r'''    if (gdata->data.follow_view && snakes_len > 0) {
      snake* me = gdata->data.snakes + (snakes_len - 1);
      gdata->data.view_xx = me->xx + me->fx + gdata->data.fvx;
      gdata->data.view_yy = me->yy + me->fy + gdata->data.fvy;
      /* Look ahead (OM, 2026-10-05): slither's camera sits ahead of the
         snake; off, the offset is zero. */
      mobile_controls_look_ahead_step(env);
      float ahead_x, ahead_y;
      mobile_controls_look_ahead_offset(env, &ahead_x, &ahead_y);
      if (gdata->data.gsc > 0.0f) {
        gdata->data.view_xx += ahead_x / gdata->data.gsc;
        gdata->data.view_yy += ahead_y / gdata->data.gsc;
      }
    }'''),
  ],
}  # end PLAY_FEEL_PAIRS
for _relative, _pairs in PLAY_FEEL_PAIRS.items():
    _arrow_patch(_relative, [(o.replace('VLITHER_ANDROID', 'WYRM_MOBILE'),
                              n.replace('VLITHER_ANDROID', 'WYRM_MOBILE')) for o, n in _pairs])
print('Play feel: original arrow motion, look ahead, arrow shadow, spring zoom')

# Your own leaderboard row (OM, 2026-10-05), Wyrm and Near Original: the
# same C as Wyrm Android's game/ui_overlay.c, applied last.
LEADERBOARD_ME_PAIRS = [
    (r'''        /* Your own row sits on a soft ink pill. */
        if (mine)
          ImDrawList_AddRectFilled(
              draw, (ImVec2){board_min.x - 6.0f, row_y - 1.0f},
              (ImVec2){board_max.x + 6.0f, row_y + row_height - 1.0f},
              hud_colour(WYRM_HALO.x, WYRM_HALO.y, WYRM_HALO.z, 0.34f),
              row_height * 0.5f, 0);
''',
     r'''        /* Your own row (OM, 2026-10-05: so you see at once where you are): the
           ink pill, lifted with a Wyrm-green tint and edge, and your name
           nudged right. */
        float me_shift = mine ? 8.0f : 0.0f;
        if (mine) {
          ImVec2 pill_min = {board_min.x - 6.0f, row_y - 1.0f};
          ImVec2 pill_max = {board_max.x + 6.0f, row_y + row_height - 1.0f};
          ImDrawList_AddRectFilled(
              draw, pill_min, pill_max,
              hud_colour(WYRM_HALO.x, WYRM_HALO.y, WYRM_HALO.z, 0.42f),
              row_height * 0.5f, 0);
          ImDrawList_AddRectFilled(draw, pill_min, pill_max,
                                   hud_colour(0.247f, 0.933f, 0.588f, 0.16f),
                                   row_height * 0.5f, 0);
          ImDrawList_AddRect(draw, pill_min, pill_max,
                             hud_colour(0.247f, 0.933f, 0.588f, 0.55f),
                             row_height * 0.5f, 0, 1.5f);
        }
'''),
    (r'''        float name_x = board_min.x + rank_size.x + 10.0f;
        wyrm_halo_fitted(''',
     r'''        float name_x = board_min.x + rank_size.x + 10.0f + me_shift;
        wyrm_halo_fitted('''),
    (r'''    float y = ly + (5.0f + 14.0f * row_y) * u;
    char rank[8];
    snprintf(rank, sizeof(rank), "#%d", row + 1);
    original_text(draw, bold, size, (ImVec2){lx, y}, colour, alpha, rank);''',
     r'''    float y = ly + (5.0f + 14.0f * row_y) * u;
    /* Your own row (OM, 2026-10-05): a faint plate behind it and the rank and
       name nudged right, so you see at once where you are. */
    float me_x = mine ? 6.0f * u : 0.0f;
    if (mine)
      ImDrawList_AddRectFilled(
          draw, (ImVec2){lx - 6.0f * u, y - 1.5f * u},
          (ImVec2){lx + 247.0f * u, y + size + 2.5f * u},
          igColorConvertFloat4ToU32((ImVec4){1, 1, 1, 0.14f * original_lb_fade}),
          6.0f * u, 0);
    char rank[8];
    snprintf(rank, sizeof(rank), "#%d", row + 1);
    original_text(draw, bold, size, (ImVec2){lx + me_x, y}, colour, alpha, rank);'''),
    (r'''      original_text(draw, bold, size, (ImVec2){lx + 28.0f * u, y}, colour, alpha, fitted);''',
     r'''      original_text(draw, bold, size, (ImVec2){lx + 28.0f * u + me_x, y}, colour, alpha, fitted);'''),
]  # end LEADERBOARD_ME_PAIRS
_arrow_patch('app/src/game/ui_overlay.c', LEADERBOARD_ME_PAIRS)
print('Leaderboard: your own row stands out')

# Auto restart (OM, 2026-10-05): the on-screen toggle in the rope-mode slot;
# a kill is answered with Restart. The same C as Wyrm Android, applied last.
AUTO_RESTART_PAIRS = {
  'app/src/mobile/mobile_hotkeys.c': [
    (r'''    "Boost",       "Turn left",  "Turn right", "Fullscreen", "Rope mode"};''',
     r'''    "Boost",       "Turn left",  "Turn right", "Fullscreen", "Auto restart"};'''),
    (r'''         action == MOBILE_HOTKEY_ZOOM_IN ||
         action == MOBILE_HOTKEY_ZOOM_OUT;
}''',
     r'''         action == MOBILE_HOTKEY_ZOOM_IN ||
         action == MOBILE_HOTKEY_ZOOM_OUT ||
         /* Auto restart (OM, 2026-10-05) lives in the rope-mode slot. */
         action == MOBILE_HOTKEY_ROPE_MODE;
}'''),
    (r'''    for (int action = 0; action < NUM_MOBILE_ACTIONS; ++action) {
      if (!mobile_hotkey_is_on_screen_button(action)) continue;
      if (!WYRM_EXPERIMENTAL_ROPE_MODE &&
          action == MOBILE_HOTKEY_ROPE_MODE)
        continue;
      bool visible = false;''',
     r'''    for (int action = 0; action < NUM_MOBILE_ACTIONS; ++action) {
      if (!mobile_hotkey_is_on_screen_button(action)) continue;
      bool visible = false;'''),
    (r'''  if (action == MOBILE_HOTKEY_ROPE_MODE)
    return env->usr->mobile_hotkeys.rope_mode;''',
     r'''  /* The rope-mode slot is the Auto restart toggle now: lit while it is on. */
  if (action == MOBILE_HOTKEY_ROPE_MODE)
    return WYRM_EXPERIMENTAL_ROPE_MODE ? env->usr->mobile_hotkeys.rope_mode
                                       : env->usr->usrs.auto_respawn != 0;'''),
    (r'''    if (!mobile_hotkey_is_on_screen_button(action)) continue;
    if (!WYRM_EXPERIMENTAL_ROPE_MODE && action == MOBILE_HOTKEY_ROPE_MODE)
      continue;
    bool visible = false;
    mobile_hotkey_get_layout(&env->usr->usrs, action, &visible, NULL, NULL);
    if (!visible) continue;''',
     r'''    if (!mobile_hotkey_is_on_screen_button(action)) continue;
    bool visible = false;
    mobile_hotkey_get_layout(&env->usr->usrs, action, &visible, NULL, NULL);
    if (!visible) continue;'''),
    (r'''    ImVec2 size;
    igCalcTextSize(&size, function, NULL, false, -1);
    igPopFont();
    ImDrawList_AddText_FontPtr(
        draw, font, font->LegacySize,
        (ImVec2){cx - size.x * 0.5f, cy - size.y * 0.5f}, primary, function,
        NULL, 0, NULL);''',
     r'''    ImVec2 size;
    igCalcTextSize(&size, function, NULL, false, -1);
    igPopFont();
    /* A longer name ("Auto restart") is set smaller to stay inside the key. */
    float text_size = font->LegacySize;
    float room = width - 16.0f;
    if (size.x > room && size.x > 0.0f) {
      text_size *= room / size.x;
      size.x = room;
      size.y *= text_size / font->LegacySize;
    }
    ImDrawList_AddText_FontPtr(
        draw, font, text_size,
        (ImVec2){cx - size.x * 0.5f, cy - size.y * 0.5f}, primary, function,
        NULL, 0, NULL);'''),
  ],
  'app/src/game/input.c': [
    (r'''       mobile_hotkeys_pressed(env, MOBILE_HOTKEY_ROPE_MODE)))
    env->usr->mobile_hotkeys.rope_mode = !env->usr->mobile_hotkeys.rope_mode;
''',
     r'''       mobile_hotkeys_pressed(env, MOBILE_HOTKEY_ROPE_MODE)))
    env->usr->mobile_hotkeys.rope_mode = !env->usr->mobile_hotkeys.rope_mode;

  /* Auto restart (OM, 2026-10-05): the on-screen toggle in the rope-mode slot.
     On, a kill is answered with Restart at once (android_home_notify_death).
     Kept in `auto_respawn`, which user.dat already holds. */
  if (!WYRM_EXPERIMENTAL_ROPE_MODE &&
      mobile_hotkeys_pressed(env, MOBILE_HOTKEY_ROPE_MODE)) {
    usrs->auto_respawn = usrs->auto_respawn ? 0 : 1;
    save_user_settings(usrs);
  }
'''),
  ],
  'app/src/platform/android_settings.c': [
    (r'''    if (!mobile_hotkey_is_on_screen_button(action)) continue;
    if (!WYRM_EXPERIMENTAL_ROPE_MODE && action == MOBILE_HOTKEY_ROPE_MODE)
      continue;
''',
     r'''    if (!mobile_hotkey_is_on_screen_button(action)) continue;
'''),
    (r'''    {"layout.stats_scale", "layout", "", "", SETTING_FLOAT, 0.65f, 1.60f,''',
     r'''    /* Auto restart (OM, 2026-10-05): the on-screen toggle's state, so it goes
       to the account. Never listed as a row. */
    {"general.auto_respawn", "layout", "", "", SETTING_INT, 0, 1, NULL,
     OWNER_SETTINGS, SETTINGS_FIELD(auto_respawn)},
    {"layout.stats_scale", "layout", "", "", SETTING_FLOAT, 0.65f, 1.60f,'''),
  ],
  'app/src/platform/android_home.c': [
    (r'''static bool run_recorded = false;
''',
     r'''static bool run_recorded = false;
/* Auto restart (OM, 2026-10-05): this death's restart is closing the socket. */
static bool auto_restart_closing = false;
'''),
    (r'''  env->usr->gdata.data.follow_view = false;
  env->usr->gdata.data.lagging = false;
  env->usr->gdata.data.lag_mult = 1;
  env->usr->gdata.restart_req = false;
  env->usr->gdata.leaving = false;
  death_watching = true;''',
     r'''  /* Auto restart (OM, 2026-10-05): with the on-screen toggle on, a kill is
     answered with Restart at once, as if the Restart key were pressed: no
     death wait, no lobby. Only for a real kill on an open arena socket (a
     drop still goes to the lobby and its report), and never during a
     champion's victory exchange. The rejoin keeps the arena's cooldowns. */
  game_data* auto_gdata = &env->usr->gdata;
  /* A second death report while that restart closes changes nothing. */
  if (auto_restart_closing && auto_gdata->restart_req) return;
  auto_restart_closing = false;
  if (env->usr->usrs.auto_respawn && auto_gdata->connection &&
      auto_gdata->join_spawned && !auto_gdata->data.victory_message_requested) {
    death_watching = false;
    death_active = false;
    auto_gdata->data.follow_view = false;
    auto_gdata->leaving = false;
    auto_gdata->restart_req = true;
    auto_restart_closing = true;
    game_close_connection(auto_gdata, "auto restart");
    SDL_Log("Wyrm death: auto restart");
    return;
  }
  env->usr->gdata.data.follow_view = false;
  env->usr->gdata.data.lagging = false;
  env->usr->gdata.data.lag_mult = 1;
  env->usr->gdata.restart_req = false;
  env->usr->gdata.leaving = false;
  death_watching = true;'''),
  ],
}  # end AUTO_RESTART_PAIRS
for _relative, _pairs in AUTO_RESTART_PAIRS.items():
    _arrow_patch(_relative, [(o.replace('VLITHER_ANDROID', 'WYRM_MOBILE'),
                              n.replace('VLITHER_ANDROID', 'WYRM_MOBILE')) for o, n in _pairs])
print('Auto restart: on-screen toggle, a kill restarts at once')

SKINLESS_SPINE_PAIRS = {
  'app/src/game/user_settings.h': [
    (r'''#include <stdint.h>
''', r'''#include <stdint.h>
#include <stddef.h>
'''),
    (r'''} mobile_hotkey_label_mode;

typedef struct user_settings {''', r'''} mobile_hotkey_label_mode;

/* Settings added after v2.8 (OM, 2026-10-05). The file stays "2.8": this
   block is found by its magic and carries its own size, so a file written
   before a field existed reads back with that field at its default and
   nothing before it is lost; a newer file read by an older build simply
   has a longer tail the older build ignores.
   RULE: every new persistent setting from now on is appended at the END of
   this block (never in the middle, never elsewhere in user_settings) and
   gets its default in user_settings_ext_default(). */
#define USER_SETTINGS_EXT_MAGIC 0x54584557u /* "WEXT" */
typedef struct user_settings_ext {
  uint32_t magic;
  uint32_t size; /* sizeof(user_settings_ext) of the build that wrote it */
  bool spine[2];              /* normal, assist (OM, 2026-10-05) */
  bool assist_hide_cosmetics; /* assist only (OM, 2026-10-05) */
} user_settings_ext;

typedef struct user_settings {'''),
    (r'''  float hud_chat_opacity;
} user_settings;
''', r'''  float hud_chat_opacity;

  /* Appended after v2.8 without a version bump (OM, 2026-10-05). */
  user_settings_ext ext;
} user_settings;

void user_settings_ext_default(user_settings_ext* ext);
/* True when a missing or damaged ext field was put back, so the caller saves. */
bool user_settings_ext_fix(user_settings* settings, size_t bytes_read);
'''),
  ],
  'app/src/game/user_settings.c': [
    (r'''void user_settings_default(user_settings* usr_settings) {
''', r'''static void user_settings_ext_default(user_settings_ext* x) {
  memset(x, 0, sizeof(*x));
  x->magic = USER_SETTINGS_EXT_MAGIC;
  x->size = (uint32_t)sizeof(user_settings_ext);
  x->spine[0] = false;
  x->spine[1] = false;
  x->assist_hide_cosmetics = false;
}

/* A bool is one byte. A value other than 0 or 1 is not a bool this build wrote. */
static bool ext_take_bool(bool* field, int present) {
  unsigned char byte = 0;
  if (!present) {
    *field = false;
    return true;
  }
  memcpy(&byte, field, 1);
  *field = byte == 1;
  return byte > 1;
}

bool user_settings_ext_fix(user_settings* settings, size_t bytes_read) {
  user_settings_ext* ext = &settings->ext;
  size_t ext_at = offsetof(user_settings, ext);
  size_t spine0 = offsetof(user_settings_ext, spine);
  size_t hide_at = offsetof(user_settings_ext, assist_hide_cosmetics);
  int fixed;
  uint32_t written;
  if (bytes_read < ext_at + 8 || ext->magic != USER_SETTINGS_EXT_MAGIC ||
      ext->size < 8) {
    user_settings_ext_default(ext);
    return true;
  }
  written = ext->size;
  fixed = 0;
  fixed |= ext_take_bool(&ext->spine[0], written >= spine0 + 1);
  fixed |= ext_take_bool(&ext->spine[1], written >= spine0 + 2);
  fixed |= ext_take_bool(&ext->assist_hide_cosmetics, written >= hide_at + 1);
  /* A longer tail belongs to a newer build. Do not shrink it just to rewrite
     the size we already understood. A shorter one is missing fields, so save. */
  if (written < (uint32_t)sizeof(user_settings_ext)) fixed = 1;
  ext->magic = USER_SETTINGS_EXT_MAGIC;
  ext->size = (uint32_t)sizeof(user_settings_ext);
  return fixed != 0;
}

void user_settings_default(user_settings* usr_settings) {
'''),
    (r'''  user_settings_default_layout_appearance(usr_settings);

  // normal mode
''', r'''  user_settings_default_layout_appearance(usr_settings);
  user_settings_ext_default(&usr_settings->ext);

  // normal mode
'''),
    (r'''void read_user_settings(user_settings* usr_settings) {
  FILE* f = fopen(USER_SETTINGS_FILE, "rb");
''', r'''void read_user_settings(user_settings* usr_settings) {
  user_settings_ext_default(&usr_settings->ext);
  FILE* f = fopen(USER_SETTINGS_FILE, "rb");
'''),
    (r'''  bool current = file_size == (long)sizeof(recovered);
  bool v26 = file_size == (long)v26_size;
  bool v25 = file_size == (long)v25_size;
  bool v21 = file_size == (long)v21_size;
  bool v20 = file_size == (long)v20_size;
  size_t want = current ? sizeof(recovered)
                        : v26 ? v26_size
                              : v25 ? v25_size : v21 ? v21_size : v20_size;
  bool valid =
      (current || v26 || v25 || v21 || v20) &&
      fread(&recovered, want, 1, file) == 1;
  int trailing = fgetc(file);
  fclose(file);
  valid = valid && trailing == EOF &&
''', r'''  const size_t ext_at = offsetof(user_settings, ext);
  bool current = file_size >= (long)ext_at &&
                 file_size <= (long)sizeof(recovered) + 4096;
  bool v26 = file_size == (long)v26_size;
  bool v25 = file_size == (long)v25_size;
  bool v21 = file_size == (long)v21_size;
  bool v20 = file_size == (long)v20_size;
  size_t want = current ? ((size_t)file_size < sizeof(recovered)
                               ? (size_t)file_size
                               : sizeof(recovered))
                        : v26 ? v26_size
                              : v25 ? v25_size : v21 ? v21_size : v20_size;
  bool valid =
      (current || v26 || v25 || v21 || v20) &&
      fread(&recovered, 1, want, file) == want;
  int trailing = current ? EOF : fgetc(file);
  fclose(file);
  valid = valid && trailing == EOF &&
'''),
    (r'''  if (valid && v26) user_settings_reset_hud_layout(&recovered);
''', r'''  if (valid && v26) user_settings_reset_hud_layout(&recovered);
  if (valid && current) user_settings_ext_fix(&recovered, want);
'''),
    (r'''  size_t read = fread(usr_settings, sizeof(user_settings), 1, f);
  fclose(f);
''', r'''  const size_t ext_at = offsetof(user_settings, ext);
  size_t read_bytes = 0;
  int read_ok = 0;
  if (file_size >= (long)ext_at) {
    size_t want = (size_t)file_size < sizeof(user_settings) ? (size_t)file_size
                                                           : sizeof(user_settings);
    read_bytes = fread(usr_settings, 1, want, f);
    read_ok = read_bytes == want;
  }
  fclose(f);
'''),
    (r'''  if (read == 1 && strncmp(usr_settings->version, "1.8", 3) == 0) {
    usr_settings->auto_respawn = 0;
    strcpy(usr_settings->version, SETTINGS_VERSION);
    save_user_settings(usr_settings);
    return;
  }

  if (read != 1 || strncmp(usr_settings->version, SETTINGS_VERSION,
                           strlen(SETTINGS_VERSION)) != 0) {
''', r'''  if (read_ok && strncmp(usr_settings->version, "1.8", 3) == 0) {
    usr_settings->auto_respawn = 0;
    user_settings_ext_default(&usr_settings->ext);
    strcpy(usr_settings->version, SETTINGS_VERSION);
    save_user_settings(usr_settings);
    return;
  }

  if (!read_ok || strncmp(usr_settings->version, SETTINGS_VERSION,
                          strlen(SETTINGS_VERSION)) != 0) {
'''),
    (r'''  if (sanitize_mobile_controls(&usr_settings->mobile_controls))
    save_user_settings(usr_settings);
''', r'''  if (user_settings_ext_fix(usr_settings, read_bytes))
    save_user_settings(usr_settings);

  if (sanitize_mobile_controls(&usr_settings->mobile_controls))
    save_user_settings(usr_settings);
'''),
    (r'''  strcpy(usr_settings->version, SETTINGS_VERSION);
  FILE* file = fopen(USER_SETTINGS_TEMP_FILE, "wb");
''', r'''  strcpy(usr_settings->version, SETTINGS_VERSION);
  usr_settings->ext.magic = USER_SETTINGS_EXT_MAGIC;
  usr_settings->ext.size = (uint32_t)sizeof(user_settings_ext);
  FILE* file = fopen(USER_SETTINGS_TEMP_FILE, "wb");
'''),
    (r'''static void user_settings_ext_default(user_settings_ext* x) {
''', r'''void user_settings_ext_default(user_settings_ext* x) {
'''),
  ],
  'app/src/platform/android_update.c': [
    (r'''      mode->boost_type > 1 || mode->render_mode < 0 || mode->render_mode > 2 ||
''', r'''      mode->boost_type > 1 || mode->render_mode < 0 || mode->render_mode > 3 ||
'''),
    (r'''  user_settings merged = {0};
  FILE* current = fopen(USER_SETTINGS_FILE, "rb");
  bool have_current =
      current && fread(&merged, sizeof(merged), 1, current) == 1;
  if (current) fclose(current);
  if (!have_current) user_settings_default(&merged);
''', r'''  user_settings merged = {0};
  FILE* current = fopen(USER_SETTINGS_FILE, "rb");
  bool have_current = false;
  if (current) {
    long size = 0;
    fseek(current, 0, SEEK_END);
    size = ftell(current);
    rewind(current);
    user_settings_ext_default(&merged.ext);
    if (size >= (long)offsetof(user_settings, ext)) {
      size_t want = (size_t)size < sizeof(merged) ? (size_t)size : sizeof(merged);
      have_current = fread(&merged, 1, want, current) == want;
      if (have_current) user_settings_ext_fix(&merged, want);
    }
    fclose(current);
  }
  if (!have_current) user_settings_default(&merged);
'''),
    (r'''    memcpy(&merged.joystick_opacity, &source.joystick_opacity,
           sizeof(user_settings) - offsetof(user_settings, joystick_opacity));
''', r'''    memcpy(&merged.joystick_opacity, &source.joystick_opacity,
           offsetof(user_settings, ext) - offsetof(user_settings, joystick_opacity));
'''),
  ],
  'app/src/platform/android_settings.c': [
    (r'''    {"assist.head_dot_color", "assist", "Dot colour", "", SETTING_COLOR3,
     0, 1, NULL, OWNER_SETTINGS,
     SETTINGS_FIELD(head_dot_color) + sizeof(vec3)},
''', r'''    {"assist.head_dot_color", "assist", "Dot colour", "", SETTING_COLOR3,
     0, 1, NULL, OWNER_SETTINGS,
     SETTINGS_FIELD(head_dot_color) + sizeof(vec3)},
    {"normal.spine", "normal", "Spine",
     "A thin white line down the middle of every snake.", SETTING_BOOL, 0, 1,
     NULL, OWNER_SETTINGS, SETTINGS_FIELD(ext.spine[0])},
    {"assist.spine", "assist", "Spine",
     "A thin white line down the middle of every snake.", SETTING_BOOL, 0, 1,
     NULL, OWNER_SETTINGS, SETTINGS_FIELD(ext.spine[1])},
    {"assist.hide_cosmetics", "assist", "Hide own tag and accessories",
     "While assist is on, your tag, accessory and Wyrm look are hidden.",
     SETTING_BOOL, 0, 1, NULL, OWNER_SETTINGS,
     SETTINGS_FIELD(ext.assist_hide_cosmetics)},
'''),
    (r'''    {"render_mode", "Snake rendering", "", SETTING_ENUM, 0, 2,
     "Texture|Solid|Flat", MODE_FIELD(render_mode)},
''', r'''    {"render_mode", "Snake rendering", "", SETTING_ENUM, 0, 3,
     "Texture|Solid|Flat|Skinless", MODE_FIELD(render_mode)},
'''),
    (r'''static void write_field(tenv* env, const char* id, const float* values,
                        int count) {
''', r'''static void clamp_written(const char* id, void* field, setting_type type) {
  float lo = 0.0f;
  float hi = 0.0f;
  int found = 0;
  int i;
  const char* dot;
  const char* name;
  for (i = 0; i < (int)(sizeof(GLOBAL_FIELDS) / sizeof(GLOBAL_FIELDS[0])); ++i) {
    if (strcmp(GLOBAL_FIELDS[i].id, id) != 0) continue;
    lo = GLOBAL_FIELDS[i].minimum;
    hi = GLOBAL_FIELDS[i].maximum;
    found = 1;
    break;
  }
  if (!found) {
    dot = strchr(id, '.');
    name = dot ? dot + 1 : id;
    for (i = 0; i < (int)(sizeof(MODE_FIELDS) / sizeof(MODE_FIELDS[0])); ++i) {
      if (strcmp(MODE_FIELDS[i].id, name) != 0) continue;
      lo = MODE_FIELDS[i].minimum;
      hi = MODE_FIELDS[i].maximum;
      found = 1;
      break;
    }
  }
  if (!found || lo > hi) return;
  if (type == SETTING_FLOAT) {
    float value = *(float*)field;
    if (value < lo) *(float*)field = lo;
    else if (value > hi) *(float*)field = hi;
    return;
  }
  {
    int value = *(int*)field;
    if (value < (int)lo) *(int*)field = (int)lo;
    else if (value > (int)hi) *(int*)field = (int)hi;
  }
}

static void write_field(tenv* env, const char* id, const float* values,
                        int count) {
'''),
    (r'''    case SETTING_INT:
    case SETTING_ENUM:
      *(int*)field = (int)(values[0] + (values[0] < 0 ? -0.5f : 0.5f));
      break;
    case SETTING_FLOAT:
      *(float*)field = values[0];
      break;
''', r'''    case SETTING_INT:
    case SETTING_ENUM:
      *(int*)field = (int)(values[0] + (values[0] < 0 ? -0.5f : 0.5f));
      clamp_written(id, field, type);
      break;
    case SETTING_FLOAT:
      *(float*)field = values[0];
      clamp_written(id, field, type);
      break;
'''),
  ],
  'app/src/game/ai_mode.c': [
    (r'''static bool editor_bare;
static bool bare_assist_saved;
static bool bare_assist_was;
void ai_mode_set_editor_bare(bool bare) { editor_bare = bare; }
''', r'''static bool editor_bare;
static bool bare_assist_saved;
static bool bare_assist_was;
/* The snake-look preview (OM, 2026-10-05): the bare editor shows the mode
   the Modes page is on, so assist can be forced on as well as off. */
static bool bare_assist_on;
void ai_mode_set_editor_bare(bool bare) { editor_bare = bare; }
void ai_mode_set_editor_assist(bool on) { bare_assist_on = on; }
'''),
    (r'''  if (editor_bare) e->usr->usrs.hotkeys[HOTKEY_ASSIST].active = false;
''', r'''  if (editor_bare) e->usr->usrs.hotkeys[HOTKEY_ASSIST].active = bare_assist_on;
'''),
    (r'''void ai_mode_finish_editor(tenv* e) {
  if (bare_assist_saved) {
    e->usr->usrs.hotkeys[HOTKEY_ASSIST].active = bare_assist_was;
    bare_assist_saved = false;
  }
  editor_bare = false;
  editor_session = false;
  ai_mode_stop(e);
  e->usr->gdata.curr_screen = TITLE_SCREEN;
}
''', r'''void ai_mode_finish_editor(tenv* e) {
  bool assist_forced = false;
  if (bare_assist_saved) {
    assist_forced =
        e->usr->usrs.hotkeys[HOTKEY_ASSIST].active != bare_assist_was;
    e->usr->usrs.hotkeys[HOTKEY_ASSIST].active = bare_assist_was;
    bare_assist_saved = false;
  }
  bare_assist_on = false;
  editor_bare = false;
  editor_session = false;
  ai_mode_stop(e);
  e->usr->gdata.curr_screen = TITLE_SCREEN;
  /* A live write during the preview saved the forced assist flag with it. */
  if (assist_forced) save_user_settings(&e->usr->usrs);
}
'''),
    (r'''  if (editor_session) {
    int count = tdarray_length(g->data.snakes);
''', r'''  if (editor_session) {
    if (editor_bare)
      e->usr->usrs.hotkeys[HOTKEY_ASSIST].active = bare_assist_on;
    int count = tdarray_length(g->data.snakes);
'''),
  ],
  'app/src/game/ai_mode.h': [
    (r'''void ai_mode_set_editor_bare(bool bare);
''', r'''void ai_mode_set_editor_bare(bool bare);
void ai_mode_set_editor_assist(bool on);
'''),
  ],
  'app/src/game/redraw.c': [
    (r'''void redraw(tenv* env) {
''', r'''
/* Skinless strip and the spine (OM, 2026-10-05). ImGui is drawn after the
   sprite batches, so a line here covers the body. Eyes for these modes are
   circles on the same list and therefore sit on top. */
static void snake_screen_point(const game_data* gdata, int point, float cx,
                               float cy, ImVec2* out) {
  out->x = cx + (gdata->data.pbx[point] - gdata->data.view_xx) * gdata->data.gsc;
  out->y = cy + (gdata->data.pby[point] - gdata->data.view_yy) * gdata->data.gsc;
}

static void stroke_smooth(ImDrawList* draw, ImVec2* pts, int count, ImU32 col,
                          float width) {
  int i;
  if (count < 2 || width <= 0.0f) return;
  ImDrawList_PathClear(draw);
  ImDrawList_PathLineTo(draw, pts[0]);
  for (i = 1; i < count - 1; ++i) {
    ImVec2 mid;
    mid.x = (pts[i].x + pts[i + 1].x) * 0.5f;
    mid.y = (pts[i].y + pts[i + 1].y) * 0.5f;
    ImDrawList_PathBezierQuadraticCurveTo(draw, pts[i], mid, 0);
  }
  ImDrawList_PathLineTo(draw, pts[count - 1]);
  ImDrawList_PathStroke(draw, col, 0, width);
}

/* On-screen runs only. A full buffer is stroked and continued from its last
   point so a long snake does not need a 32k stack. */
static void draw_body_line(tenv* env, int bp, int start, float cx, float cy,
                           ImU32 under, float under_w, ImU32 over, float over_w) {
  game_data* gdata = &env->usr->gdata;
  ImDrawList* draw = igGetWindowDrawList();
  ImVec2 buf[160];
  int n = 0;
  int i;
  for (i = start; i <= bp; ++i) {
    int live = i < bp && gdata->data.pbu[i] >= 1;
    if (live && n < 160) {
      snake_screen_point(gdata, i, cx, cy, &buf[n]);
      n += 1;
      if (n < 160) continue;
    }
    if (n >= 2) {
      if (under_w > 0.0f) stroke_smooth(draw, buf, n, under, under_w);
      stroke_smooth(draw, buf, n, over, over_w);
    }
    if (live) {
      buf[0] = buf[n > 0 ? n - 1 : 0];
      n = 1;
    } else {
      n = 0;
    }
  }
}

static void snake_strip_colour(tenv* env, snake* o, float* red, float* green,
                               float* blue) {
  game_data* gdata = &env->usr->gdata;
  uint32_t built = built_skin_rgba(env, o, 0);
  int cg_id;
  vec3s* col;
  if (built) {
    *red = (float)((built >> 16) & 255) / 255.0f;
    *green = (float)((built >> 8) & 255) / 255.0f;
    *blue = (float)(built & 255) / 255.0f;
    return;
  }
  cg_id = o->cusk && o->cusk_len > 0 ? o->cusk_data[0]
                                    : gdata->default_skins[o->cv][1];
  col = gdata->cg_colors + cg_id;
  *red = col->r;
  *green = col->g;
  *blue = col->b;
}

static float snake_line_dpi(tenv* env) {
  float dpi = 1.0f;
  int w;
  int h;
  float short_side;
  if (!env->wnd) return dpi;
  w = env->wnd->size[0];
  h = env->wnd->size[1];
  short_side = (float)(w < h ? w : h);
  dpi = short_side / 480.0f;
  if (dpi < 1.0f) dpi = 1.0f;
  return dpi;
}

/* One smooth run. Round caps are the plain discs' ends (NTL lineCap). */
static void draw_skinless_run(ImDrawList* draw, ImVec2* buf, int n, ImU32 col,
                              float width, int cap_start, int cap_end) {
  float radius;
  if (n < 1 || width <= 0.0f) return;
  if (n >= 2) stroke_smooth(draw, buf, n, col, width);
  radius = width * 0.5f;
  if (cap_start) ImDrawList_AddCircleFilled(draw, buf[0], radius, col, 24);
  if (cap_end && n >= 2)
    ImDrawList_AddCircleFilled(draw, buf[n - 1], radius, col, 24);
}

/* Skinless, like NTL's of() (OM, 2026-10-05). lsz is already half of 29*sc,
   so a plain disc is 2 * lsz * gsc across and this stroke is that wide.
   Round caps add that radius at each real end, which is the disc. Alpha is
   NTL's skinless transparency: .8 times the snake's own fade. Runs continue
   past 160 points so a long snake is not cut short. */
static void draw_skinless_strip(tenv* env, snake* o, int bp, float cx, float cy,
                                float lsz, float alpha) {
  game_data* gdata = &env->usr->gdata;
  ImDrawList* draw = igGetWindowDrawList();
  ImVec2 buf[160];
  int n = 0;
  int i;
  int continued = 0;
  float red, green, blue;
  float width = 2.0f * lsz * gdata->data.gsc;
  ImU32 main_col;
  ImU32 glow_col;
  int boosting = o->tsp > o->fsp;
  snake_strip_colour(env, o, &red, &green, &blue);
  main_col = igColorConvertFloat4ToU32((ImVec4){red, green, blue, 0.8f * alpha});
  glow_col = igColorConvertFloat4ToU32((ImVec4){red, green, blue, 0.22f * alpha});
  for (i = 0; i <= bp; ++i) {
    int live = i < bp && gdata->data.pbu[i] >= 1;
    int more;
    int cap_start;
    int cap_end;
    if (live && n < 160) {
      snake_screen_point(gdata, i, cx, cy, &buf[n]);
      n += 1;
      if (n < 160) continue;
    }
    if (n >= 1) {
      more = live;
      cap_start = !continued;
      cap_end = !more;
      if (boosting)
        draw_skinless_run(draw, buf, n, glow_col, width * 1.08f, cap_start,
                          cap_end);
      draw_skinless_run(draw, buf, n, main_col, width, cap_start, cap_end);
    }
    if (live) {
      buf[0] = buf[n > 0 ? n - 1 : 0];
      n = 1;
      continued = 1;
    } else {
      n = 0;
      continued = 0;
    }
  }
}

static void draw_snake_spine(tenv* env, int bp, float cx, float cy, float alpha) {
  float dpi = snake_line_dpi(env);
  ImU32 dark = igColorConvertFloat4ToU32((ImVec4){0.0f, 0.0f, 0.0f, 0.35f * alpha});
  ImU32 white = igColorConvertFloat4ToU32((ImVec4){1.0f, 1.0f, 1.0f, 0.8f * alpha});
  draw_body_line(env, bp, 1, cx, cy, dark, 4.0f * dpi, white, 2.0f * dpi);
}

static void draw_snake_imgui_eyes(tenv* env, snake* o, float fang, float hx,
                                  float hy, float ssc, float ea, float cx,
                                  float cy) {
  game_data* gdata = &env->usr->gdata;
  default_skin_data* dfs = gdata->dfs + ((1 - o->cusk) * (1 + o->cv));
  float ed = 6 * ssc;
  float esp = 6 * ssc;
  float iris_r = 6 * ssc * gdata->data.gsc;
  float pupil_r = dfs->pr * ssc * gdata->data.gsc;
  ImDrawList* draw = igGetWindowDrawList();
  ImU32 iris = igColorConvertFloat4ToU32((ImVec4){dfs->ec.r, dfs->ec.g, dfs->ec.b, ea});
  ImU32 pupil =
      igColorConvertFloat4ToU32((ImVec4){dfs->ppc.r, dfs->ppc.g, dfs->ppc.b, ea});
  float side;
  float ex;
  float ey;
  ImVec2 at;
  for (side = -1.0f; side <= 1.0f; side += 2.0f) {
    ex = cosf(fang) * ed + cosf(fang + side * (PI / 2)) * (esp + 0.5f);
    ey = sinf(fang) * ed + sinf(fang + side * (PI / 2)) * (esp + 0.5f);
    at.x = cx + (ex + hx - gdata->data.view_xx) * gdata->data.gsc;
    at.y = cy + (ey + hy - gdata->data.view_yy) * gdata->data.gsc;
    ImDrawList_AddCircleFilled(draw, at, iris_r, iris, 16);
    ex = cosf(fang) * (ed + 0.5f) + o->rex * ssc +
         cosf(fang + side * (PI / 2)) * esp;
    ey = sinf(fang) * (ed + 0.5f) + o->rey * ssc +
         sinf(fang + side * (PI / 2)) * esp;
    at.x = cx + (ex + hx - gdata->data.view_xx) * gdata->data.gsc;
    at.y = cy + (ey + hy - gdata->data.view_yy) * gdata->data.gsc;
    ImDrawList_AddCircleFilled(draw, at, pupil_r, pupil, 12);
  }
}

void redraw(tenv* env) {
'''),
    (r'''                          {cg_col->r, cg_col->g, cg_col->b, a}});
                }
            }
          }

          // debugging
''', r'''                          {cg_col->r, cg_col->g, cg_col->b, a}});
                }
            }
          } else if (mode->render_mode == 3) {
            /* Skinless: the plain body's width and length, skin see-through. */
            draw_skinless_strip(env, o, bp, mww2, mhh2, lsz, a);
          }

          // debugging
'''),
    (r'''          if (mode->show_boost) {
''', r'''          if (mode->show_boost && mode->render_mode != 3) {
'''),
    (r'''          // draw eyes:
          float ed = 6 * ssc;   // o->ed
          float esp = 6 * ssc;  // o->esp
          float er = 6;         // o->er
          default_skin_data* dfs = gdata->dfs + ((1 - o->cusk) * (1 + o->cv));
          float pr = dfs->pr;
          float iris_r = er * ssc * gdata->data.gsc;
          float pupil_r = pr * ssc * gdata->data.gsc;

          float ex = cosf(fang) * ed + cosf(fang - PI / 2) * (esp + .5);
          float ey = sinf(fang) * ed + sinf(fang - PI / 2) * (esp + .5);

          float ea = mode->death_effect
                         ? o->alive_amt * o->alive_amt * sqrtf(1 - o->dead_amt)
                         : a;

          bp_renderer_push(
              usr->r->bpr,
              &(bp_instance){
                  {(mww2 + (ex + hx - gdata->data.view_xx) * gdata->data.gsc) -
                       iris_r,
                   (mhh2 + (ey + hy - gdata->data.view_yy) * gdata->data.gsc) -
                       iris_r,
                   iris_r * 2, 0},
                  gdata->cg_uvs[BLANK_UV],
                  {dfs->ec.r, dfs->ec.g, dfs->ec.b, ea}});

          ex = cosf(fang) * ed + cosf(fang + PI / 2) * (esp + .5);
          ey = sinf(fang) * ed + sinf(fang + PI / 2) * (esp + .5);

          bp_renderer_push(
              usr->r->bpr,
              &(bp_instance){
                  {(mww2 + (ex + hx - gdata->data.view_xx) * gdata->data.gsc) -
                       iris_r,
                   (mhh2 + (ey + hy - gdata->data.view_yy) * gdata->data.gsc) -
                       iris_r,
                   iris_r * 2, 0},
                  gdata->cg_uvs[BLANK_UV],
                  {dfs->ec.r, dfs->ec.g, dfs->ec.b, ea}});

          ex =
              cosf(fang) * (ed + .5) + o->rex * ssc + cosf(fang - PI / 2) * esp;
          ey =
              sinf(fang) * (ed + .5) + o->rey * ssc + sinf(fang - PI / 2) * esp;

          bp_renderer_push(
              usr->r->bpr,
              &(bp_instance){
                  {(mww2 + (ex + hx - gdata->data.view_xx) * gdata->data.gsc) -
                       pupil_r,
                   (mhh2 + (ey + hy - gdata->data.view_yy) * gdata->data.gsc) -
                       pupil_r,
                   pupil_r * 2, 0},
                  gdata->cg_uvs[BLANK_UV],
                  {dfs->ppc.r, dfs->ppc.g, dfs->ppc.b, ea}});

          ex =
              cosf(fang) * (ed + .5) + o->rex * ssc + cosf(fang + PI / 2) * esp;
          ey =
              sinf(fang) * (ed + .5) + o->rey * ssc + sinf(fang + PI / 2) * esp;

          bp_renderer_push(
              usr->r->bpr,
              &(bp_instance){
                  {(mww2 + (ex + hx - gdata->data.view_xx) * gdata->data.gsc) -
                       pupil_r,
                   (mhh2 + (ey + hy - gdata->data.view_yy) * gdata->data.gsc) -
                       pupil_r,
                   pupil_r * 2, 0},
                  gdata->cg_uvs[BLANK_UV],
                  {dfs->ppc.r, dfs->ppc.g, dfs->ppc.b, ea}});

''', r'''          // draw eyes:
          float ed = 6 * ssc;   // o->ed
          float esp = 6 * ssc;  // o->esp
          float er = 6;         // o->er
          default_skin_data* dfs = gdata->dfs + ((1 - o->cusk) * (1 + o->cv));
          float pr = dfs->pr;
          float iris_r = er * ssc * gdata->data.gsc;
          float pupil_r = pr * ssc * gdata->data.gsc;

          float ex = cosf(fang) * ed + cosf(fang - PI / 2) * (esp + .5);
          float ey = sinf(fang) * ed + sinf(fang - PI / 2) * (esp + .5);

          float ea = mode->death_effect
                         ? o->alive_amt * o->alive_amt * sqrtf(1 - o->dead_amt)
                         : a;

          /* Spine sits on the ImGui list, which is drawn after the sprites,
             so eyes for a spine or a skinless strip are circles on that list
             and end up on top (OM, 2026-10-05). */
          {
            int assist_on = usrs->hotkeys[HOTKEY_ASSIST].active ? 1 : 0;
            int spine_on = usrs->ext.spine[assist_on] ? 1 : 0;
            if (spine_on) draw_snake_spine(env, bp, mww2, mhh2, a);
            if (mode->render_mode == 3 || spine_on)
              draw_snake_imgui_eyes(env, o, fang, hx, hy, ssc, ea, mww2, mhh2);
            else {
          bp_renderer_push(
              usr->r->bpr,
              &(bp_instance){
                  {(mww2 + (ex + hx - gdata->data.view_xx) * gdata->data.gsc) -
                       iris_r,
                   (mhh2 + (ey + hy - gdata->data.view_yy) * gdata->data.gsc) -
                       iris_r,
                   iris_r * 2, 0},
                  gdata->cg_uvs[BLANK_UV],
                  {dfs->ec.r, dfs->ec.g, dfs->ec.b, ea}});

          ex = cosf(fang) * ed + cosf(fang + PI / 2) * (esp + .5);
          ey = sinf(fang) * ed + sinf(fang + PI / 2) * (esp + .5);

          bp_renderer_push(
              usr->r->bpr,
              &(bp_instance){
                  {(mww2 + (ex + hx - gdata->data.view_xx) * gdata->data.gsc) -
                       iris_r,
                   (mhh2 + (ey + hy - gdata->data.view_yy) * gdata->data.gsc) -
                       iris_r,
                   iris_r * 2, 0},
                  gdata->cg_uvs[BLANK_UV],
                  {dfs->ec.r, dfs->ec.g, dfs->ec.b, ea}});

          ex =
              cosf(fang) * (ed + .5) + o->rex * ssc + cosf(fang - PI / 2) * esp;
          ey =
              sinf(fang) * (ed + .5) + o->rey * ssc + sinf(fang - PI / 2) * esp;

          bp_renderer_push(
              usr->r->bpr,
              &(bp_instance){
                  {(mww2 + (ex + hx - gdata->data.view_xx) * gdata->data.gsc) -
                       pupil_r,
                   (mhh2 + (ey + hy - gdata->data.view_yy) * gdata->data.gsc) -
                       pupil_r,
                   pupil_r * 2, 0},
                  gdata->cg_uvs[BLANK_UV],
                  {dfs->ppc.r, dfs->ppc.g, dfs->ppc.b, ea}});

          ex =
              cosf(fang) * (ed + .5) + o->rex * ssc + cosf(fang + PI / 2) * esp;
          ey =
              sinf(fang) * (ed + .5) + o->rey * ssc + sinf(fang + PI / 2) * esp;

          bp_renderer_push(
              usr->r->bpr,
              &(bp_instance){
                  {(mww2 + (ex + hx - gdata->data.view_xx) * gdata->data.gsc) -
                       pupil_r,
                   (mhh2 + (ey + hy - gdata->data.view_yy) * gdata->data.gsc) -
                       pupil_r,
                   pupil_r * 2, 0},
                  gdata->cg_uvs[BLANK_UV],
                  {dfs->ppc.r, dfs->ppc.g, dfs->ppc.b, ea}});

            }
          }

'''),
    (r'''          tags_draw(env, o, o->id == gdata->data.snake_id, false);
''', r'''          const int hide_own_cosmetics =
              usrs->hotkeys[HOTKEY_ASSIST].active &&
              usrs->ext.assist_hide_cosmetics &&
              o->id == gdata->data.snake_id;
          if (!hide_own_cosmetics)
          tags_draw(env, o, o->id == gdata->data.snake_id, false);
'''),
    (r'''          if (mode->show_accessories && o->accessory < NUM_ACCESSORIES) {
''', r'''          if (!hide_own_cosmetics && mode->show_accessories && o->accessory < NUM_ACCESSORIES) {
'''),
    (r'''          tags_draw(env, o, true, false);
''', r'''          if (!(usrs->hotkeys[HOTKEY_ASSIST].active &&
                usrs->ext.assist_hide_cosmetics))
          tags_draw(env, o, true, false);
'''),
  ],
}  # end SKINLESS_SPINE_PAIRS
for _relative, _pairs in SKINLESS_SPINE_PAIRS.items():
    _arrow_patch(_relative, [(o.replace('VLITHER_ANDROID', 'WYRM_MOBILE'),
                              n.replace('VLITHER_ANDROID', 'WYRM_MOBILE')) for o, n in _pairs])
_arrow_patch('app/src/game/redraw.c', [
    (r'''          if (o->id == gdata->data.snake_id) {
            extern void wyrm_look_draw(tenv* env, float hx, float hy, float fang,
                                       float lsz, float alpha, float mww2,
                                       float mhh2);
            wyrm_look_draw(env, hx, hy, fang, lsz, ea, mww2, mhh2);
          }
''', r'''          if (!hide_own_cosmetics && o->id == gdata->data.snake_id) {
            extern void wyrm_look_draw(tenv* env, float hx, float hy, float fang,
                                       float lsz, float alpha, float mww2,
                                       float mhh2);
            wyrm_look_draw(env, hx, hy, fang, lsz, ea, mww2, mhh2);
          }
'''),
])
print('Skinless + spine + assist hide + settings ext')

# Auto restart key can be shown (OM, 2026-10-05): the old rope-mode lock
# hid slot 14 on every save. Same C as Wyrm Android, applied last.
AUTO_RESTART_VISIBLE_PAIRS = [
    (r'''  if (settings->rope_mode_visible) {
    settings->rope_mode_visible = false;
    changed = true;
  }
  return changed;
}
''',
     r'''  /* Slot 14 is the Auto restart key now (OM, 2026-10-05). It used to be
     forced hidden here for the old rope mode, which hid Auto restart on every
     save; its visibility is the player's choice. */
  return changed;
}
'''),
]  # end AUTO_RESTART_VISIBLE_PAIRS
_arrow_patch('app/src/game/user_settings.c', AUTO_RESTART_VISIBLE_PAIRS)
print('Auto restart: its key can be shown')
