#ifndef WYRM_ORIENTATION_POLICY_H
#define WYRM_ORIENTATION_POLICY_H

/* Main-thread presentation reducer, also executed by the portable harness.
   Targets: 0 portrait app, 1 portrait game, 2 landscape game. */
typedef enum {
  WYRM_ORIENTATION_WAIT, WYRM_ORIENTATION_PRESENT_GAME,
  WYRM_ORIENTATION_RETURN_HOME, WYRM_ORIENTATION_CHANGE_MASK
} WyrmOrientationAction;
static inline WyrmOrientationAction wyrm_orientation_action(
    int wanted, int current, int game_exists, int transitioning,
    int foreground, int home_attached, int other_modal, int geometry_api) {
  if (wanted < 0 || wanted > 2 || transitioning || !foreground) return WYRM_ORIENTATION_WAIT;
  if (game_exists) {
    if (current == wanted) return WYRM_ORIENTATION_WAIT;
    if (wanted > 0 && geometry_api) return WYRM_ORIENTATION_CHANGE_MASK;
    return WYRM_ORIENTATION_RETURN_HOME;
  }
  if (wanted == 0 || !home_attached || other_modal) return WYRM_ORIENTATION_WAIT;
  return WYRM_ORIENTATION_PRESENT_GAME;
}
#endif
