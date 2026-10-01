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

  /* The smallest period p with groups[i] == groups[i - p] for every i >= p. */
  int period = count;
  for (int p = 1; p < count; p++) {
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
             'record_finished_run': '''extern void WyrmIOSRecordFinishedRun(int score, int kills, double play_time);
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
        clamp = 'index = ARENA_PERSONA_AIR;'
        assert text.count(clamp) == 1
        text = text.replace(clamp, 'index = ARENA_PERSONA_WEB;')
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
        text = apply_run_capture(text)
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
JOYSTICK_LASER_DRAW = ('            usrs->laser_thickness);\n      }\n', "            usrs->laser_thickness);\n      }\n\n      /* Assist laser in joystick mode (OM, 2026-10-01). With assist on and a\n         joystick (not the arrow, which has its own line), a line from the head\n         where the snake is being steered: the stick's way while it is held,\n         the head's own heading otherwise. Its length is a share of the\n         screen's short side, set in Settings > Modes > Assist; colour and\n         thickness are the laser's. Draw-only: no input, no packet. */\n      if (usrs->hotkeys[HOTKEY_ASSIST].active &&\n          usrs->mobile_controls.joystick_mode != MOBILE_STEERING_ARROW &&\n          android_home_joystick_laser_on() && a > 0.01f) {\n        mobile_controls_state* stick = &usr->mobile_controls;\n        float lx = cosf(me->ehang);\n        float ly = sinf(me->ehang);\n        float held = sqrtf(stick->joystick_axis[0] * stick->joystick_axis[0] +\n                           stick->joystick_axis[1] * stick->joystick_axis[1]);\n        if (stick->joystick_down && held > 0.08f) {\n          lx = stick->joystick_axis[0] / held;\n          ly = stick->joystick_axis[1] / held;\n        }\n        float shortest = ctx->size[0] < ctx->size[1] ? (float)ctx->size[0]\n                                                     : (float)ctx->size[1];\n        float reach = android_home_joystick_laser_length() * shortest;\n        ImVec2 from = {mww2 + (hx - gdata->data.view_xx) * gdata->data.gsc,\n                       mhh2 + (hy - gdata->data.view_yy) * gdata->data.gsc};\n        ImDrawList_AddLine(\n            igGetWindowDrawList(), from,\n            (ImVec2){from.x + lx * reach, from.y + ly * reach},\n            igColorConvertFloat4ToU32(\n                (ImVec4){usrs->laser_color[0], usrs->laser_color[1],\n                         usrs->laser_color[2], usrs->laser_color[3] * a}),\n            usrs->laser_thickness);\n      }\n")
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
