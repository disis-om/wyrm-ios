"""Wyrm's own arena floors (OM, 2026-10-01), appended after the original 22.

One list for both scripts: prepare-original-engine.py adds the rows to the
engine's backgrounds.h and copies Resources/Backgrounds/*.png into the res
tree; generate-swift-skin-catalog.py adds them to the Swift catalog. Wyrm
Android's app/src/game/backgrounds.h has the same rows, in the same order
(the index is what is stored and synced). The PNGs and sizes come from Wyrm
Android's tools/generate-focus-backgrounds.py.
"""

# (key, label, file in Resources/Backgrounds or None, tile_w, tile_h)
EXTRA_BACKGROUNDS = [
    ("black", "Black", None, 512.0, 512.0),
    ("wyrm_midnight", "Midnight", "wyrm_midnight.png", 3790.04, 3282.27),
    ("wyrm_carbon", "Carbon", "wyrm_carbon.png", 2954.04, 2954.04),
    ("wyrm_abyss", "Abyss", "wyrm_abyss.png", 7002.18, 7002.18),
    ("wyrm_nebula", "Nebula", "wyrm_nebula.png", 7002.18, 7002.18),
    ("wyrm_dotgrid", "Dot grid", "wyrm_dotgrid.png", 2735.23, 2735.23),
    ("wyrm_contours", "Contours", "wyrm_contours.png", 7002.18, 7002.18),
    ("wyrm_scales", "Scales", "wyrm_scales.png", 3282.27, 3282.27),
    # Round two (OM, 2026-10-15): 30-48, nine dark then ten soft (append only).
    ("wyrm_ember", "Ember", "wyrm_ember.png", 5251.63, 5251.63),
    ("wyrm_dunes", "Dunes", "wyrm_dunes.png", 7002.18, 7002.18),
    ("wyrm_moss", "Moss", "wyrm_moss.png", 5251.63, 5251.63),
    ("wyrm_cells", "Cells", "wyrm_cells.png", 6154.26, 6154.26),
    ("wyrm_aurora", "Aurora", "wyrm_aurora.png", 7002.18, 7002.18),
    ("wyrm_facets", "Facets", "wyrm_facets.png", 5470.45, 5470.45),
    ("wyrm_frost", "Frost", "wyrm_frost.png", 5251.63, 5251.63),
    ("wyrm_tartan", "Tartan", "wyrm_tartan.png", 3282.27, 3282.27),
    ("wyrm_reptile", "Reptile", "wyrm_reptile.png", 6154.26, 6154.26),
    ("wyrm_sage", "Sage", "wyrm_sage.png", 3501.09, 3501.09),
    ("wyrm_shore", "Shore", "wyrm_shore.png", 7002.18, 7002.18),
    ("wyrm_terrazzo", "Terrazzo", "wyrm_terrazzo.png", 5251.63, 5251.63),
    ("wyrm_mist", "Mist", "wyrm_mist.png", 7002.18, 7002.18),
    ("wyrm_lavender", "Lavender", "wyrm_lavender.png", 3411.04, 2954.04),
    ("wyrm_clay", "Clay", "wyrm_clay.png", 2625.82, 2625.82),
    ("wyrm_paper", "Paper", "wyrm_paper.png", 2735.23, 2735.23),
    ("wyrm_seafoam", "Seafoam", "wyrm_seafoam.png", 3501.09, 1750.54),
    ("wyrm_marble", "Marble", "wyrm_marble.png", 7002.18, 7002.18),
    ("wyrm_pebbles", "Pebbles", "wyrm_pebbles.png", 5251.63, 5251.63),
]

# Engine index of Black (22: right after the original 22).
BLACK_INDEX = 22

# The pickers' order (ids stay the engine's): Wyrm, Black, None, Wyrm's own,
# then the imported set.
DISPLAY_ORDER = [0, 22, 1] + list(range(23, 30)) + list(range(30, 49)) + list(range(2, 22))


def engine_row(key, label, file, tile_w, tile_h):
    path = "NULL" if file is None else f'"app/res/textures/backgrounds/{file}"'
    return f'    {{"{key}", "{label}", {path}, {tile_w:.2f}f, {tile_h:.2f}f}},'
