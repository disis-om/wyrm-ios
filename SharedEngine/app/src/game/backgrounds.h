#ifndef BACKGROUNDS_H
#define BACKGROUNDS_H

/**
 * The arenas' floors.
 *
 * Each entry is one seamlessly tiling image plus the world-space size of a
 * single tile. The size is not the pixel size and is not optional: the shader
 * divides a world position by it to get the sampling coordinate, so a wrong
 * number is a pattern that stretches or seams. These are the sizes the
 * reference client declares for the same images, kept exactly.
 *
 * `BACKGROUND_NONE` is the absence of one rather than an image of black: the
 * renderer drops the background pass entirely, which is cheaper than sampling a
 * texture that is the same colour as the clear.
 */
typedef struct background_def {
  const char* id;    /* stable, stored in settings and never reordered */
  const char* label; /* what a player sees */
  const char* path;  /* NULL for the ones that draw nothing */
  float tile_w;
  float tile_h;
} background_def;

enum {
  BACKGROUND_WYRM = 0,
  BACKGROUND_NONE = 1,
};

/**
 * Order is the grid order and the stored value, so entries are only ever
 * appended. Wyrm's own first, then nothing, then the imported set.
 */
static const background_def BACKGROUNDS[] = {
    {"wyrm", "Wyrm", "app/res/textures/background_4k.png", 4096.0f, 3548.0f},
    {"none", "None", NULL, 512.0f, 512.0f},
    {"classic", "Classic", "app/res/textures/backgrounds/bgee_classic.png", 599.0f, 519.0f},
    {"bgee2", "Slither", "app/res/textures/backgrounds/bgee2.png", 800.0f, 800.0f},
    {"asanoha", "Asanoha", "app/res/textures/backgrounds/bg_asanoha.png", 600.0f, 520.0f},
    {"seigaiha", "Seigaiha", "app/res/textures/backgrounds/bg_seigaiha.png", 801.0f, 810.0f},
    {"graygrid", "Grey grid", "app/res/textures/backgrounds/bg_graygrid.png", 768.0f, 768.0f},
    {"rizz", "Rizz", "app/res/textures/backgrounds/bg_rizz.png", 800.0f, 794.0f},
    {"usastar", "Stars", "app/res/textures/backgrounds/bg_usastar.png", 599.0f, 519.0f},
    {"circuits", "Circuits", "app/res/textures/backgrounds/bg_circuits.png", 800.0f, 800.0f},
    {"circuits2", "Circuits II", "app/res/textures/backgrounds/bg_circuits2.png", 800.0f, 800.0f},
    {"hexice", "Hex ice", "app/res/textures/backgrounds/bg_hexice.png", 800.0f, 800.0f},
    {"hexb", "Hex", "app/res/textures/backgrounds/bg_hexB.png", 800.0f, 693.0f},
    {"hearts", "Hearts", "app/res/textures/backgrounds/bg_hearts.png", 800.0f, 781.0f},
    {"leaves", "Leaves", "app/res/textures/backgrounds/bg_leaves.png", 800.0f, 800.0f},
    {"paint", "Paint", "app/res/textures/backgrounds/bg_paint.png", 800.0f, 800.0f},
    {"snakey", "Snakey", "app/res/textures/backgrounds/bg_snakey.png", 800.0f, 800.0f},
    {"stainedglass", "Stained glass", "app/res/textures/backgrounds/bg_stainedglass.png", 800.0f, 800.0f},
    {"kitties", "Kitties", "app/res/textures/backgrounds/bg_kitties.png", 800.0f, 786.0f},
    {"bluecube", "Blue cube", "app/res/textures/backgrounds/bg_bluecube.png", 872.0f, 882.0f},
    {"purplecube", "Purple cube", "app/res/textures/backgrounds/bg_purplecube.png", 872.0f, 882.0f},
    {"redcube", "Red cube", "app/res/textures/backgrounds/bg_redcube.png", 872.0f, 882.0f},
};

enum { NUM_BACKGROUNDS = (int)(sizeof(BACKGROUNDS) / sizeof(BACKGROUNDS[0])) };

/** Any stored value that is no longer in the table falls back to Wyrm's own. */
static inline int background_clamp(int index) {
  return (index >= 0 && index < NUM_BACKGROUNDS) ? index : BACKGROUND_WYRM;
}

#endif
