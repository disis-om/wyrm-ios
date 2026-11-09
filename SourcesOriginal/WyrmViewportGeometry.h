#ifndef WYRM_VIEWPORT_GEOMETRY_H
#define WYRM_VIEWPORT_GEOMETRY_H

/* Actual window coordinates, independent of UIKit, used by native Rain layout
   and executable geometry tests. Apple and the portable harness use Clang. */
typedef struct { double left, top, width, height, offset_x, offset_y; } WyrmPanelGeometry;
static inline double wyrm_panel_max(double a, double b) { return a > b ? a : b; }
static inline double wyrm_panel_min(double a, double b) { return a < b ? a : b; }
static inline double wyrm_panel_finite(double x, double fallback) { return __builtin_isfinite(x) ? x : fallback; }
static inline WyrmPanelGeometry wyrm_panel_geometry(
    double sw, double sh, double wanted_w, double wanted_h, double ox, double oy,
    double left, double top, double right, double bottom) {
  WyrmPanelGeometry result = {0};
  sw = wyrm_panel_max(0, wyrm_panel_finite(sw, 0));
  sh = wyrm_panel_max(0, wyrm_panel_finite(sh, 0));
  left = wyrm_panel_min(sw, wyrm_panel_max(0, wyrm_panel_finite(left, 0)));
  right = wyrm_panel_min(sw - left, wyrm_panel_max(0, wyrm_panel_finite(right, 0)));
  top = wyrm_panel_min(sh, wyrm_panel_max(0, wyrm_panel_finite(top, 0)));
  bottom = wyrm_panel_min(sh - top, wyrm_panel_max(0, wyrm_panel_finite(bottom, 0)));
  double aw = sw - left - right, ah = sh - top - bottom;
  if (aw <= 0 || ah <= 0) return result;
  wanted_w = wyrm_panel_max(1, wyrm_panel_finite(wanted_w, 380));
  wanted_h = wyrm_panel_max(1, wyrm_panel_finite(wanted_h, 340));
  double fit = wyrm_panel_min(1, wyrm_panel_min(aw / wanted_w, ah / wanted_h));
  result.width = wanted_w * fit; result.height = wanted_h * fit;
  double cx = (sw - result.width) / 2, cy = (sh - result.height) / 2;
  result.left = wyrm_panel_min(sw - right - result.width, wyrm_panel_max(left, cx + wyrm_panel_finite(ox, 0)));
  result.top = wyrm_panel_min(sh - bottom - result.height, wyrm_panel_max(top, cy + wyrm_panel_finite(oy, 0)));
  result.offset_x = result.left - cx; result.offset_y = result.top - cy;
  return result;
}
#endif
