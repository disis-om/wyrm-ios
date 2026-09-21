#ifndef SNAKE_H
#define SNAKE_H

#include "body_part.h"
#include "gpt.h"
#include <stddef.h>
#include <stdint.h>

typedef struct snake {
  int id;
  /*
   * NTL's team service does not identify a snake with the raw arena id.
   * Packet `S` replaces its high six bits with a session discriminator and
   * the mod publishes that 16-bit value as `sid`.  Keep both identities so a
   * team row can be resolved back to the snake the renderer actually owns.
   */
  int ntl_id;
  bool local_player;
  int cv;
  int fpos;
  int ftg;
  int fapos;
  int fatg;
  int flpos;
  int fltg;
  int sct;
  int cusk_len;
  int dir;
  int rsc;
  int iiv;
  int edir;
  uint32_t kill_count;
  char admin_ip[16];
  char original_nickname[256];
  bool point_check_mismatch;

  float xx;
  float yy;
  float chl;
  float tsp;
  float sfr;
  float sc;
  float ssp;
  float fsp;
  float msp;
  float fx;
  float fy;
  float fa;
  float ehang;
  float wehang;
  float ang;
  float eang;
  float wang;
  float spang;
  float rex;
  float rey;
  float sp;
  float fl;
  float tl;
  float cfl;
  float scang;
  float dead_amt;
  float alive_amt;
  float msl;
  float fam;
  float wsep;
  float sep;
  float fchl;
  
  float fxs[GD_EEZ];
  float fys[GD_EEZ];
  float fchls[GD_EEZ];
  float fas[GD_AFC];
  float fls[GD_EEZ];

  uint8_t accessory;
  uint8_t cusk_data[MAX_SKIN_CODE_LEN];
  char nk[MAX_NICKNAME_LEN + 1];

  bool cusk;
  bool dead;

  body_part* pts;
  gpt* gptz;
} snake;

static inline int snake_ntl_id(int arena_id, uint32_t session_id) {
  return (int)((((session_id & 63u) << 10) |
                ((uint32_t)arena_id & 1023u)) & 65535u);
}

static inline snake* snake_find_by_ntl_id(snake* snakes, int count,
                                          int ntl_id) {
  for (int i = count - 1; i >= 0; --i)
    if (snakes[i].ntl_id == ntl_id) return snakes + i;
  return NULL;
}

#endif
