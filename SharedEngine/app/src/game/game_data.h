#ifndef GAME_DATA_H
#define GAME_DATA_H

#include <thermite.h>

#include "../external/mongoose.h"
#include "snake.h"
#include "food.h"
#include "prey.h"
#include "sbot.h"

typedef struct default_skin_data {
  vec3s ec;
  vec3s ppc;
  float pr;
} default_skin_data;

typedef struct leaderboard {
  struct {
    char nickname[MAX_NICKNAME_LEN + 1];
    int score;
    int cv;
  } entries[NUM_LEADERBOARD_ENTRIES];
} leaderboard;

typedef struct accessory_data {
  vec4s uv;
  float sc;
  float of;
} accessory_data;

#define MAX_REMOTE_SKINS 128

/**
 * Another Wyrm player's built skin, learned from Wyrm's own backend rather than
 * from the arena.
 *
 * The arena carries colour-group indices and has no field for an exact colour,
 * so this is the only way one Wyrm client can see what another actually built.
 * The nickname is kept because arenas recycle snake ids between lives: a row is
 * only used while the snake wearing that id still answers to the same name.
 */
typedef struct remote_skin {
  int snake_id;
  char nickname[MAX_NICKNAME_LEN + 1];
  int length;
  uint32_t rgba[MAX_SKIN_CODE_LEN];
  uint64_t last_used_ms;
} remote_skin;

typedef struct game_data {
  screen curr_screen;
  conn_status conn;
  bool ai_mode;

  /* Grows with the arena population and is capped by LRU, rather than making
   * the first 24 Wyrm snakes permanent for the whole match. */
  remote_skin* remote_skins;
  
  uint8_t default_skins[NUM_DEFAULT_SKINS][64];
  char ntl_cg_map[NUM_COLOR_GROUPS];
  vec4s cg_uvs[NUM_COLOR_GROUPS];
  vec3s cg_colors[NUM_COLOR_GROUPS]; // original rgbs
  accessory_data accessories[NUM_ACCESSORIES];
  vec3s cg_glow_colors[NUM_COLOR_GROUPS]; // glow color rgbs
  bool cg_colors_ct[NUM_COLOR_GROUPS]; // original rgbs' contrasts
  float worm_effect[WORM_EFFECT_LEN]; // skin effect for default skins
  float fsz[NUM_FOOD_SIZES]; // food sizes
  float psz[NUM_PREY_SIZES]; // prey sizes
  default_skin_data dfs[NUM_DEFAULT_SKINS + 1]; // + 1 for custom skin
  int u_m[7];
  sbot bot;

  vec4s SHADOW_UV;
  vec4s CURSOR_UV;
  vec4s SKIN_LESS_UV;

  struct mg_mgr network_manager;
  struct mg_connection* connection;

  bool restart_req;
  bool closed;

  /* A join that never became visible, and whether the player asked to leave.
     Arenas go stale — the picker's list is a snapshot of servers that come and
     go — so a socket that opens and shuts again before the snake ever exists
     is a dead address rather than a decision the player made. */
  int join_attempts;
  bool leaving;
  /* Set while the player is in the native lobby session. Death and a refused
     join return here instead of Compose Home. Home on the lobby clears it. */
  bool stay_in_lobby;
  uint64_t rejoin_at_ms;

  /* A spawn is admission. It used to be only that — the match was held behind
     the connecting screen for a further 1.2s and only a join that survived it
     was shown — but the hold existed to hide a retry that no longer happens,
     so `finish_stable_join` reveals the match on the next frame. What is left
     distinguishes a first join, which is probated and may be retried, from a
     restart inside a match the player has already seen. */
  bool join_spawned;
  bool join_visible;
  bool join_requires_stability;
  /* Server configuration accepted; independent of the first visible snake. */
  bool arena_ready;
  double life_started_sec;
  /* When this entry began, for the whole-entry budget the reference client
     uses instead of a fixed attempt count. */
  uint64_t join_started_ms;

  /* Who hung up. Every close arrives at the same event whether the player left,
     the engine restarted, or the arena dropped us — this is the only thing
     that tells them apart, and not knowing cost an afternoon. */
  bool closed_by_us;
  double last_life;

  /* Which client Wyrm is claiming to be, as an index into the persona table in
     `network/arena_persona.h`. The retry path alternates it, and a match that
     lasts writes the one that worked back into the settings file. */
  int persona;

  /* Whether this attempt got far enough to put the persona to the test — that
     is, whether an arena challenged us and we answered.

     Most failed attempts never open a WebSocket at all: the arena refuses the
     connection and nothing is sent or received. A refusal at that level says
     nothing whatever about which client we were claiming to be, so alternating
     the persona on one would spend half of a fourteen-second entry proving an
     identity that was never in question. */
  bool persona_tested;

  /* When the current attempt dialled, in SDL ticks. The join timeout is
     measured off this rather than off `glfwGetTime()`, which several other
     things in Wyrm rewind. */
  uint64_t attempt_started_ms;

  /* When a socket was last opened to any arena. Survives `game_data_reset`,
     because the whole point of it is to pace one entry against the last. */
  uint64_t last_connect_ms;

  /* Set when auto-respawn is answering a death that came too fast to have been
     a match. It is what tells the restart path to wait out the longer cooldown
     instead of dialling straight back into an arena that is refusing us. */
  bool respawn_after_short_life;

  struct {
    int sector_count_along_edge;
    int real_sid;
    int game_mode;
    int team_value;
    bool victory_message_requested;
    bool want_close_socket;
    bool admin_data;
    uint32_t session_id;
    int session_snake_id;
    int32_t team_scores[2];
    int32_t team_score_history[128][2];
    unsigned team_history_count;
    int victory_score;
    char victory_nick[256];
    char victory_message[1024];
    /* W adds membership; w removes it. Separate from food storage. */
    struct arena_sector { int x, y; } *sectors;
    float grd;
    float sector_size;
    float ssd256;
    float spangdv;
    float nsp1;
    float nsp2;
    float nsp3;
    float mamu;
    float mamu2;
    float cst;
    float default_msl;
    float ovxx;
    float ovyy;
    float flux_grd;
    float real_flux_grd;
    float view_xx;
    float view_yy;
    float lview_xx;
    float lview_yy;
    float lfsx;
    float lfsy;
    float lfcv;
    float lfvsx;
    float lfvsy;
    float gsc;
    float lag_mult;
    float etm;
    float ltm;
    float ctm;
    float vfr;
    float avfr;
    float last_ping_mtm;
    float last_accel_mtm;
    float last_e_mtm;
    float fps_etm;
    float fps_ltm;
    float fr;
    float fvx;
    float fvy;
    float bpx1;
    float bpy1;
    float bpx2;
    float bpy2;
    float fpx1;
    float fpy1;
    float fpx2;
    float fpy2;
    float ping_follow;
    float ms_zoom;
    float lkstm;

    double play_etm;

    int lsxm;
    int lsym;
    int mmsz;
    int fvpos;
    int fvtg;
    int flx_tg;
    int flux_grd_pos;
    int mscps;
    int protocol_version;
    int lfesid;
    int lsang;
    int vfrb;
    int frames;
    int fps;
    int cping;
    int ping;
    int score;
    int lb_pos;
    int rank;
    int slither_count;
    int kills;
    int snake_id;
    int kd_l_frb;
    int kd_r_frb;

    float* fmlts;
    float* fpsls;
    
    float pings[PING_SAMPLE_COUNT];
    float xfas[GD_EEZ];
    float afas[GD_AFC];
    float vfas[GD_VFC];
    float fvxs[GD_VFC];
    float fvys[GD_VFC];
    float flxas[GD_FLXC];
    float flux_grds[GD_EEZ];
    float smus[GD_SMUC];
    float p12[250];
    float pbx[32767];
    float pby[32767];
    float pba[32767];

    uint8_t pbu[32767];
    uint8_t mm_data[MAX_MINIMAP_SIZE * MAX_MINIMAP_SIZE];
    uint8_t mm_team_mask[MAX_MINIMAP_SIZE * MAX_MINIMAP_SIZE];
    int minimap_team_count;
    float mm_data_follow[MAX_MINIMAP_SIZE * MAX_MINIMAP_SIZE];

    snake* snakes;
    food* foods;
    prey* preys;
    body_part** pts_dp;
    gpt** gptz_dp;

    bool wfpr;
    bool lagging;
    bool md;
    bool wmd;
    bool dead;
    bool follow_view;
    bool mmgad;
    bool gotlb;
    bool want_e;

    leaderboard lb;
  } data;

  /* When the arena last said anything, in SDL ticks. The death watch reads it:
     a socket that is still open but has stopped sending is a frozen picture,
     and there is nothing to be gained by holding the card back over one. */
  uint64_t last_packet_ms;
} game_data;

/* How long after opening a socket the next one may open. Both original clients
   pace their attempts at this, and a press inside the window is held rather
   than refused. */
enum { ARENA_CONNECT_COOLDOWN_MS = 3333 };

/* The same thing for a respawn that follows a life too short to have been a
   real match. Auto-respawn plus an arena that is throwing us out on sight is a
   loop with nothing to stop it — this is what stops it. A respawn after a match
   the player actually played is paced by the ordinary cooldown above. */
enum { ARENA_RESPAWN_LOOP_COOLDOWN_MS = 10000 };

/* A life shorter than this was not a match. Used to tell a real death from an
   arena that admitted a snake and reconsidered. */
#define SHORT_LIFE 8.0

/**
 * Asks for an arena, on the clock rather than on the button.
 *
 * The one way into a match: Home's Play, the death card's Play, and the restart
 * hotkey all arrive here. Resets the world, puts the connecting screen up, and
 * either dials now or holds the dial until `min_interval_ms` has passed since
 * the last socket was opened.
 */
void arena_request_join(tenv* env, unsigned int min_interval_ms);

void display_hotkeys(tuser_data* usr, float offset, font_size sz);

/**
 * Ends the match, on the record.
 *
 * Everything that leaves an arena goes through here, so that the close event
 * on the other side can tell a player who left from an arena that dropped
 * them. `why` is written to the log exactly as given.
 */
void game_close_connection(game_data* gdata, const char* why);

/** Ends a failed join without turning it into a player-requested departure. */
void game_fail_connection(game_data* gdata, const char* why);

void recalc_sep_mults(game_data* gdata);
void set_mscps(game_data* gdata, int nmscps);

snake* get_snake(game_data* gdata, int id);

int get_cg_id(game_data* gdata, char skin_code_cg_id);

void game_data_init(tenv* env);
void game_data_reset(tenv* env);
void game_clear_world(game_data* gdata);
void game_capture_final_score(tenv* env);
void game_data_destroy(tenv* env);

#endif
