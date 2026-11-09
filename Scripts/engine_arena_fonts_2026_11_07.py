"""Arena text in Manrope, with every script a phone can show (OM, 2026-11-07:
"some arena texts are not drawn; use Wyrm's Manrope there too").

Why names, leaderboard rows, chat and the arena's own messages went missing:
the engine's ImGui text used Liberation Sans (regular/bold), JetBrains Mono
(snake names, stats) and a variable Manrope (wyrm_body.ttf) that
stb_truetype can only draw at its default master, ExtraLight (200). None of
them has Devanagari, Bengali, Tamil, Arabic, Thai, Chinese, Korean or the
"fancy letter" blocks players use, so those names and messages drew as '?'
or nothing. ImGui was also built with 16-bit characters, so anything past
U+FFFF (𝓢𝓷𝓪𝓴𝓮 maths letters) could never be drawn (IMGUI_USE_WCHAR32 is now
set in the Android CMake and the iOS spec, for C and C++ alike). And a
name cut at the engine's 24 bytes could end in half a character.

Now:
- every arena face is Manrope cut to a fixed weight from the app's own file
  (tools/make-engine-manrope.py): medium 500 body, semibold 600 regular /
  names / stats, bold 700, extrabold 800 bold. Display (Bodoni) and Near
  Original's Nunito stay; they get the same fallbacks.
- behind each face, in order: the old Liberation Sans of the same weight
  (Latin extended, IPA small caps, Greek, Cyrillic), then the phone's own
  fonts for the other scripts. Android: /system/fonts by file name (Noto
  Devanagari, Bengali, Gurmukhi, Gujarati, Tamil, Telugu, Kannada,
  Malayalam, Odia, Arabic, Thai, Hebrew, CJK, Symbols, Symbols2, Math). iOS:
  the same scripts' system fonts found with CoreText (Main.m
  wyrm_ios_fallback_fonts). ImGui loads a glyph from a fallback only when
  the faces before it lack it, and only when it is first drawn.
- a fallback file is mapped once (mmap) and shared by every size and face.
  ImGui 1.92 copies non-owned font data per source, so it is handed over as
  owned and the allocator ignores frees of these blobs (they live as long
  as the process). A file is used only if its table directory has cmap and
  glyf/loca or CFF (no colour-only emoji fonts, no CFF2).
- names (packet s, leaderboard l) and the arena's victory text are clipped to
  whole UTF-8 characters.
Not possible with stb_truetype: colour emoji, Indic conjunct shaping and
Arabic joining / right-to-left order (letters show, unshaped). No packet,
setting or save change.

Applied once to Wyrm Android's tree and, by prepare-original-engine.py, to the
generated iOS tree.
"""
import sys
from pathlib import Path

FONT_CODE = r'''#include "ui/ui_theme.h"

/* Arena text (OM, 2026-11-07; Wyrm iOS/Scripts/engine_arena_fonts_2026_11_07.py):
   Manrope faces with Liberation Sans and the phone's own fonts behind them
   for every script Manrope lacks. */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#if defined(__ANDROID__) || defined(__APPLE__)
#include <fcntl.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <unistd.h>
#endif
#ifdef __ANDROID__
#include <dirent.h>
#endif
#if defined(WYRM_SDL_JNI) || defined(WYRM_MOBILE)
#include <SDL3/SDL.h>
#define WYRM_FONT_LOG(...) SDL_Log(__VA_ARGS__)
#else
#define WYRM_FONT_LOG(...) ((void)0)
#endif

#if defined(__APPLE__) && defined(WYRM_IOS)
/* SourcesOriginal/Main.m: the iOS system fonts for other scripts. */
int wyrm_ios_fallback_fonts(char (*paths)[1024], int* indices, int max);
#endif

typedef struct wyrm_font_blob {
  void* data;
  size_t size;
  int index; /* face in a .ttc */
} wyrm_font_blob;

#define WYRM_FONT_BLOBS 32
/* Size limits (OM, 2026-11-07, iOS build 155: right after the system fonts
   were mapped, the engine's first texture upload failed on the Simulator).
   The huge CJK collections (PingFang, Apple SD Gothic Neo, tens of MB each)
   are left out on iOS, and every platform keeps a total; each loaded file is
   logged with its size so the next run shows exactly what was taken. */
#if defined(__APPLE__)
#define WYRM_FONT_FILE_MAX (16u << 20)
#define WYRM_FONT_TOTAL_MAX (40u << 20)
#else
#define WYRM_FONT_FILE_MAX (32u << 20)
#define WYRM_FONT_TOTAL_MAX (96u << 20)
#endif
static size_t wyrm_font_blob_bytes;
static wyrm_font_blob wyrm_font_blobs[WYRM_FONT_BLOBS];
static int wyrm_font_blob_count;
static const wyrm_font_blob* wyrm_fallback_regular[WYRM_FONT_BLOBS];
static const wyrm_font_blob* wyrm_fallback_bold[WYRM_FONT_BLOBS];
static int wyrm_fallback_regular_count, wyrm_fallback_bold_count;

/* ImGui frees a source's font data with its own allocator. The blobs are
   shared by every size and face and live as long as the process: a free of
   one is ignored. */
static bool wyrm_font_blob_shared(const void* p) {
  for (int i = 0; i < wyrm_font_blob_count; ++i)
    if (wyrm_font_blobs[i].data == p) return true;
  return false;
}
static void* wyrm_imgui_alloc(size_t size, void* user) {
  (void)user;
  return malloc(size);
}
static void wyrm_imgui_free(void* p, void* user) {
  (void)user;
  if (p && !wyrm_font_blob_shared(p)) free(p);
}

static uint32_t wyrm_be32(const unsigned char* p) {
  return (uint32_t)p[0] << 24 | (uint32_t)p[1] << 16 | (uint32_t)p[2] << 8 | p[3];
}

/* A face stb_truetype can draw: cmap plus glyf+loca or CFF (not CFF2-only,
   not a colour-bitmap emoji font). */
static bool wyrm_font_face_ok(const unsigned char* d, size_t size, int index) {
  if (size < 12) return false;
  size_t face = 0;
  if (memcmp(d, "ttcf", 4) == 0) {
    if (size < 16) return false;
    uint32_t faces = wyrm_be32(d + 8);
    if (index < 0 || (uint32_t)index >= faces || 12 + 4 * (size_t)faces > size)
      return false;
    face = wyrm_be32(d + 12 + 4 * (size_t)index);
  } else if (index != 0) {
    return false;
  }
  if (face + 12 > size) return false;
  uint32_t tag = wyrm_be32(d + face);
  if (tag != 0x00010000u && tag != 0x4F54544Fu /* OTTO */ &&
      tag != 0x74727565u /* true */) return false;
  unsigned tables = (unsigned)d[face + 4] << 8 | d[face + 5];
  if (face + 12 + 16 * (size_t)tables > size) return false;
  bool cmap = false, glyf = false, loca = false, cff = false;
  for (unsigned i = 0; i < tables; ++i) {
    const unsigned char* t = d + face + 12 + 16 * (size_t)i;
    uint32_t off = wyrm_be32(t + 8), len = wyrm_be32(t + 12);
    if ((size_t)off + len > size) return false;
    if (!memcmp(t, "cmap", 4)) cmap = true;
    if (!memcmp(t, "glyf", 4)) glyf = true;
    if (!memcmp(t, "loca", 4)) loca = true;
    if (!memcmp(t, "CFF ", 4)) cff = true;
  }
  return cmap && ((glyf && loca) || cff);
}

static const wyrm_font_blob* wyrm_font_blob_load(const char* path, int index) {
  if (!path || !path[0] || wyrm_font_blob_count >= WYRM_FONT_BLOBS) return NULL;
  void* data = NULL;
  size_t size = 0;
#if defined(__ANDROID__) || defined(__APPLE__)
  int fd = open(path, O_RDONLY | O_CLOEXEC);
  if (fd < 0) return NULL;
  struct stat st;
  if (fstat(fd, &st) == 0 && st.st_size > 100 && (size_t)st.st_size <= WYRM_FONT_FILE_MAX &&
      wyrm_font_blob_bytes + (size_t)st.st_size <= WYRM_FONT_TOTAL_MAX) {
    void* map = mmap(NULL, (size_t)st.st_size, PROT_READ, MAP_PRIVATE, fd, 0);
    if (map != MAP_FAILED) {
      data = map;
      size = (size_t)st.st_size;
    }
  }
  close(fd);
#else
  FILE* f = fopen(path, "rb");
  if (!f) return NULL;
  if (fseek(f, 0, SEEK_END) == 0) {
    long n = ftell(f);
    if (n > 100 && (size_t)n <= WYRM_FONT_FILE_MAX &&
        wyrm_font_blob_bytes + (size_t)n <= WYRM_FONT_TOTAL_MAX && fseek(f, 0, SEEK_SET) == 0) {
      data = malloc((size_t)n);
      if (data && fread(data, 1, (size_t)n, f) == (size_t)n) {
        size = (size_t)n;
      } else {
        free(data);
        data = NULL;
      }
    }
  }
  fclose(f);
#endif
  if (!data) return NULL;
  if (!wyrm_font_face_ok((const unsigned char*)data, size, index)) {
#if defined(__ANDROID__) || defined(__APPLE__)
    munmap(data, size);
#else
    free(data);
#endif
    return NULL;
  }
  wyrm_font_blob_bytes += size;
  {
    const char* base = strrchr(path, '/');
    WYRM_FONT_LOG("Wyrm arena text: font %s (%u KB, face %d)", base ? base + 1 : path,
                  (unsigned)(size >> 10), index);
  }
  wyrm_font_blob* b = &wyrm_font_blobs[wyrm_font_blob_count++];
  b->data = data;
  b->size = size;
  b->index = index;
  return b;
}

static void wyrm_fallback_both(const char* path, int index) {
  const wyrm_font_blob* b = wyrm_font_blob_load(path, index);
  if (!b) return;
  wyrm_fallback_regular[wyrm_fallback_regular_count++] = b;
  wyrm_fallback_bold[wyrm_fallback_bold_count++] = b;
}

#ifdef __ANDROID__
/* The phone's fonts for scripts Manrope lacks, by file name; within a
   script the first name that exists wins (newer Android first). */
static const char* const wyrm_android_scripts[][4] = {
    {"NotoSansDevanagariUI-", "NotoSansDevanagari-", NULL},
    {"NotoSansBengaliUI-", "NotoSansBengali-", NULL},
    {"NotoSansGurmukhiUI-", "NotoSansGurmukhi-", NULL},
    {"NotoSansGujaratiUI-", "NotoSansGujarati-", NULL},
    {"NotoSansTamilUI-", "NotoSansTamil-", NULL},
    {"NotoSansTeluguUI-", "NotoSansTelugu-", NULL},
    {"NotoSansKannadaUI-", "NotoSansKannada-", NULL},
    {"NotoSansMalayalamUI-", "NotoSansMalayalam-", NULL},
    {"NotoSansOriyaUI-", "NotoSansOriya-", NULL},
    {"NotoNaskhArabicUI-", "NotoNaskhArabic-", "NotoSansArabic-", NULL},
    {"NotoSansThaiUI-", "NotoSansThai-", NULL},
    {"NotoSansHebrew-", NULL},
    {"NotoSansCJK-Regular", "NotoSansCJK", "NotoSansSC-", "DroidSansFallback"},
    {"NotoSansSymbols-Regular-Subsetted.", "NotoSansSymbols-Regular", NULL},
    {"NotoSansSymbols2-", NULL},
    {"NotoSansMath-", NULL},
};

static bool wyrm_font_name_ok(const char* name) {
  size_t n = strlen(name);
  if (n < 5) return false;
  const char* ext = name + n - 4;
  return !strcmp(ext, ".ttf") || !strcmp(ext, ".otf") || !strcmp(ext, ".ttc");
}

static void wyrm_fallbacks_android(void) {
  DIR* dir = opendir("/system/fonts");
  if (!dir) return;
  static char names[768][96];
  int count = 0;
  struct dirent* e;
  while ((e = readdir(dir)) && count < 768) {
    if (!wyrm_font_name_ok(e->d_name) || strlen(e->d_name) >= 96) continue;
    strcpy(names[count++], e->d_name);
  }
  closedir(dir);
  for (size_t s = 0; s < sizeof(wyrm_android_scripts) / sizeof(wyrm_android_scripts[0]); ++s) {
    const char* chosen = NULL;
    for (int c = 0; c < 4 && wyrm_android_scripts[s][c] && !chosen; ++c) {
      const char* prefix = wyrm_android_scripts[s][c];
      size_t len = strlen(prefix);
      const char* plain = NULL;
      for (int i = 0; i < count; ++i) {
        if (strncmp(names[i], prefix, len) != 0) continue;
        if (strstr(names[i], "Bold") || strstr(names[i], "Serif")) continue;
        if (strstr(names[i], "Regular") || strstr(names[i], "VF")) {
          chosen = names[i];
          break;
        }
        if (!plain) plain = names[i];
      }
      if (!chosen) chosen = plain;
    }
    if (!chosen) continue;
    char path[160];
    snprintf(path, sizeof(path), "/system/fonts/%s", chosen);
    wyrm_fallback_both(path, 0);
  }
}
#endif

/* Once, before the first face: Liberation Sans of each weight, then the
   platform's fonts. */
static void wyrm_fallbacks_find(void) {
  static bool found;
  if (found) return;
  found = true;
  const wyrm_font_blob* regular = wyrm_font_blob_load("app/res/fonts/regular_regular.ttf", 0);
  const wyrm_font_blob* bold = wyrm_font_blob_load("app/res/fonts/regular_bold.ttf", 0);
  if (regular) wyrm_fallback_regular[wyrm_fallback_regular_count++] = regular;
  if (bold) wyrm_fallback_bold[wyrm_fallback_bold_count++] = bold;
  else if (regular) wyrm_fallback_bold[wyrm_fallback_bold_count++] = regular;
#ifdef __ANDROID__
  wyrm_fallbacks_android();
#elif defined(__APPLE__) && defined(WYRM_IOS)
  static char paths[24][1024];
  int indices[24];
  int n = wyrm_ios_fallback_fonts(paths, indices, 24);
  for (int i = 0; i < n; ++i) wyrm_fallback_both(paths[i], indices[i]);
#endif
  WYRM_FONT_LOG("Wyrm arena text: %d fallback fonts", wyrm_fallback_regular_count);
}

/* Merges the fallbacks into the face added last (after its icons). */
static void wyrm_merge_fallbacks(ImFontAtlas* atlas, float size, bool bold) {
  const wyrm_font_blob* const* list = bold ? wyrm_fallback_bold : wyrm_fallback_regular;
  int count = bold ? wyrm_fallback_bold_count : wyrm_fallback_regular_count;
  for (int i = 0; i < count; ++i) {
    ImFontConfig* cfg = ImFontConfig_ImFontConfig();
    cfg->MergeMode = true;
    cfg->FontDataOwnedByAtlas = true; /* shared: see wyrm_imgui_free */
    cfg->FontNo = (ImU32)list[i]->index;
    ImFontAtlas_AddFontFromMemoryTTF(atlas, list[i]->data, (int)list[i]->size,
                                     size, cfg, NULL);
    ImFontConfig_destroy(cfg);
  }
}

/* A Manrope face, or the old file if the new one is missing. */
static ImFont* wyrm_add_face(ImFontAtlas* atlas, const char* path,
                             const char* old_path, float size) {
  ImFont* font = NULL;
  FILE* probe = fopen(path, "rb");
  if (probe) {
    fclose(probe);
    font = ImFontAtlas_AddFontFromFileTTF(atlas, path, size, NULL, NULL);
  }
  if (!font) font = ImFontAtlas_AddFontFromFileTTF(atlas, old_path, size, NULL, NULL);
  return font;
}
'''

LOOP_OLD = '''    usr->imgui_data.mono_font[i] = ImFontAtlas_AddFontFromFileTTF(
        io->Fonts, "app/res/fonts/mono_regular.ttf", 20 + i * 4, NULL, NULL);

    ImFontAtlas_AddFontFromFileTTF(
        io->Fonts, "app/res/fonts/iconfont.ttf", 20 + i * 4, &icons_config,
        (const ImWchar[]){0xe900, 0xeaea, 0});

    usr->imgui_data.regular_font[i] = ImFontAtlas_AddFontFromFileTTF(
        io->Fonts, "app/res/fonts/regular_regular.ttf", 20 + i * 4, NULL, NULL);

    ImFontAtlas_AddFontFromFileTTF(
        io->Fonts, "app/res/fonts/iconfont.ttf", 20 + i * 4, &icons_config,
        (const ImWchar[]){0xe900, 0xeaea, 0});

    usr->imgui_data.mono_font_bold[i] = ImFontAtlas_AddFontFromFileTTF(
        io->Fonts, "app/res/fonts/mono_bold.ttf", 20 + i * 4, NULL, NULL);

    ImFontAtlas_AddFontFromFileTTF(io->Fonts, "app/res/fonts/iconfont.ttf",
                                   20 + i * 4, &icons_config,
                                   (const ImWchar[]){0xe900, 0xeaea, 0});

    usr->imgui_data.regular_font_bold[i] = ImFontAtlas_AddFontFromFileTTF(
        io->Fonts, "app/res/fonts/regular_bold.ttf", 20 + i * 4, NULL, NULL);

    ImFontAtlas_AddFontFromFileTTF(io->Fonts, "app/res/fonts/iconfont.ttf",
                                   20 + i * 4, &icons_config,
                                   (const ImWchar[]){0xe900, 0xeaea, 0});

    /* The two faces the app itself is set in, loaded from the same files
       Compose loads, so the arena's overlay and the app's screens speak with
       one voice. The display serif carries numbers and is loaded a size larger
       at every step, because a serif at a body size reads as decoration. */
    usr->imgui_data.display_font[i] = ImFontAtlas_AddFontFromFileTTF(
        io->Fonts, "app/res/fonts/wyrm_display.ttf", 24 + i * 5, NULL, NULL);

    usr->imgui_data.body_font[i] = ImFontAtlas_AddFontFromFileTTF(
        io->Fonts, "app/res/fonts/wyrm_body.ttf", 18 + i * 4, NULL, NULL);
  }'''

LOOP_NEW = '''    /* Arena text in Manrope (OM, 2026-11-07), each face followed by its
       icons and then the fallbacks for other scripts. */
    const float px = 20 + i * 4;
    usr->imgui_data.mono_font[i] = wyrm_add_face(
        io->Fonts, "app/res/fonts/manrope_semibold.ttf",
        "app/res/fonts/mono_regular.ttf", px);

    ImFontAtlas_AddFontFromFileTTF(
        io->Fonts, "app/res/fonts/iconfont.ttf", 20 + i * 4, &icons_config,
        (const ImWchar[]){0xe900, 0xeaea, 0});
    wyrm_merge_fallbacks(io->Fonts, px, false);

    usr->imgui_data.regular_font[i] = wyrm_add_face(
        io->Fonts, "app/res/fonts/manrope_semibold.ttf",
        "app/res/fonts/regular_regular.ttf", px);

    ImFontAtlas_AddFontFromFileTTF(
        io->Fonts, "app/res/fonts/iconfont.ttf", 20 + i * 4, &icons_config,
        (const ImWchar[]){0xe900, 0xeaea, 0});
    wyrm_merge_fallbacks(io->Fonts, px, false);

    usr->imgui_data.mono_font_bold[i] = wyrm_add_face(
        io->Fonts, "app/res/fonts/manrope_bold.ttf",
        "app/res/fonts/mono_bold.ttf", px);

    ImFontAtlas_AddFontFromFileTTF(io->Fonts, "app/res/fonts/iconfont.ttf",
                                   20 + i * 4, &icons_config,
                                   (const ImWchar[]){0xe900, 0xeaea, 0});
    wyrm_merge_fallbacks(io->Fonts, px, true);

    usr->imgui_data.regular_font_bold[i] = wyrm_add_face(
        io->Fonts, "app/res/fonts/manrope_extrabold.ttf",
        "app/res/fonts/regular_bold.ttf", px);

    ImFontAtlas_AddFontFromFileTTF(io->Fonts, "app/res/fonts/iconfont.ttf",
                                   20 + i * 4, &icons_config,
                                   (const ImWchar[]){0xe900, 0xeaea, 0});
    wyrm_merge_fallbacks(io->Fonts, px, true);

    /* The two faces the app itself is set in. The display serif carries
       numbers and is loaded a size larger at every step, because a serif at
       a body size reads as decoration. Body is Manrope Medium: the app's
       variable Manrope draws at its ExtraLight master here. */
    usr->imgui_data.display_font[i] = ImFontAtlas_AddFontFromFileTTF(
        io->Fonts, "app/res/fonts/wyrm_display.ttf", 24 + i * 5, NULL, NULL);
    wyrm_merge_fallbacks(io->Fonts, 24 + i * 5, false);

    usr->imgui_data.body_font[i] = wyrm_add_face(
        io->Fonts, "app/res/fonts/manrope_medium.ttf",
        "app/res/fonts/wyrm_body.ttf", 18 + i * 4);
    wyrm_merge_fallbacks(io->Fonts, 18 + i * 4, false);
  }'''

NUNITO_OLD = '''  usr->imgui_data.nunito_bold = ImFontAtlas_AddFontFromFileTTF(
      io->Fonts, "app/res/fonts/nunito_bold.ttf", 22, NULL, NULL);
  usr->imgui_data.nunito_black = ImFontAtlas_AddFontFromFileTTF(
      io->Fonts, "app/res/fonts/nunito_black.ttf", 22, NULL, NULL);'''

NUNITO_NEW = '''  usr->imgui_data.nunito_bold = ImFontAtlas_AddFontFromFileTTF(
      io->Fonts, "app/res/fonts/nunito_bold.ttf", 22, NULL, NULL);
  wyrm_merge_fallbacks(io->Fonts, 22, true);
  usr->imgui_data.nunito_black = ImFontAtlas_AddFontFromFileTTF(
      io->Fonts, "app/res/fonts/nunito_black.ttf", 22, NULL, NULL);
  wyrm_merge_fallbacks(io->Fonts, 22, true);'''

CLIP_OLD = '''static void arena_text(char* out, size_t capacity, const uint8_t* in, size_t count) {
  /* Plain text, never a format string or markup. Bounded native storage. */
  size_t size=count<capacity-1?count:capacity-1;
  for (size_t i=0;i<size;i++) out[i]=in[i]>=32?(char)in[i]:' ';
  out[size]=0;
}'''

CLIP_NEW = '''/* A name or message cut at a byte limit can end in half a UTF-8 character,
   which draws as '?' (OM, 2026-11-07): the broken tail is dropped. */
static void wyrm_utf8_clip(char* s) {
  size_t n = strlen(s), i = n;
  int follow = 0;
  while (i > 0 && follow < 4 && ((unsigned char)s[i - 1] & 0xC0) == 0x80) {
    --i;
    ++follow;
  }
  if (i == 0) return;
  unsigned char lead = (unsigned char)s[i - 1];
  int need = lead >= 0xF0 ? 3 : lead >= 0xE0 ? 2 : lead >= 0xC0 ? 1 : 0;
  if (lead >= 0xC0 && follow < need) s[i - 1] = 0;
}

static void arena_text(char* out, size_t capacity, const uint8_t* in, size_t count) {
  /* Plain text, never a format string or markup. Bounded native storage. */
  size_t size=count<capacity-1?count:capacity-1;
  for (size_t i=0;i<size;i++) out[i]=in[i]>=32?(char)in[i]:' ';
  out[size]=0;
  wyrm_utf8_clip(out);
}'''

PAIRS = {
    "app/src/imgui_setup.c": [
        ('#include "ui/ui_theme.h"\n', FONT_CODE),
        ("  igCreateContext(NULL);", """  /* Before the context: shared font data is never freed (arena text). */
  igSetAllocatorFunctions(wyrm_imgui_alloc, wyrm_imgui_free, NULL);
  igCreateContext(NULL);"""),
        ("  for (int i = 0; i < NUM_FONT_SIZES; i++) {", """  wyrm_fallbacks_find();
  for (int i = 0; i < NUM_FONT_SIZES; i++) {"""),
        (LOOP_OLD, LOOP_NEW),
        (NUNITO_OLD, NUNITO_NEW),
    ],
    "app/src/network/callback.c": [
        (CLIP_OLD, CLIP_NEW),
        ("""      memcpy(o.nk, a + m, cp_len);
      o.nk[cp_len] = '\\0';""", """      memcpy(o.nk, a + m, cp_len);
      o.nk[cp_len] = '\\0';
      wyrm_utf8_clip(o.nk);"""),
        ("""        gdata->data.lb.entries[pos - 1].nickname[cp_len] = '\\0';""",
         """        gdata->data.lb.entries[pos - 1].nickname[cp_len] = '\\0';
        wyrm_utf8_clip(gdata->data.lb.entries[pos - 1].nickname);"""),
    ],
}


def apply(root, label="arena fonts 2026-11-07", skip_applied=False):
    for relative, pairs in PAIRS.items():
        path = Path(root) / relative
        text = path.read_text(encoding="utf-8")
        for old, new in pairs:
            if skip_applied and new in text:
                continue
            if text.count(old) != 1:
                raise SystemExit(f"{label}: anchor x{text.count(old)} in {relative}: {old[:80]!r}")
            text = text.replace(old, new)
        path.write_text(text, encoding="utf-8", newline="\n" if "build-original-source" in str(root) else "")


def revert(root, label="arena fonts 2026-11-07"):
    """Takes this pass back out of a tree (for checks of earlier passes)."""
    for relative, pairs in PAIRS.items():
        path = Path(root) / relative
        if not path.exists():
            continue
        text = path.read_text(encoding="utf-8")
        for old, new in reversed(pairs):
            if text.count(new) != 1:
                raise SystemExit(f"{label}: revert x{text.count(new)} in {relative}: {new[:80]!r}")
            text = text.replace(new, old)
        path.write_text(text, encoding="utf-8", newline="\n")


if __name__ == "__main__":
    apply(sys.argv[1], skip_applied=True)
