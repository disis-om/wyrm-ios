#include "callback.h"

#include "../game/food.h"
#include "../game/snake.h"
#include "../platform/android_home.h"
#include "../user.h"
#include "arena_persona.h"
#include "arena_protocol.h"
#include "arena_trace.h"
#include "server.h"

void snl(game_data* gdata, snake* o) {
  float orl = o->tl;
  o->tl = o->sct + fminf(1, o->fam);
  float d = o->tl - orl;
  int k = o->flpos;
  for (int j = 0; j < GD_EEZ; j++) {
    o->fls[k] -= d * gdata->data.xfas[j];
    k++;
    if (k >= GD_EEZ) k = 0;
  }
  o->fl = o->fls[o->flpos];
  o->fltg = GD_EEZ;
}

void decode_secret(const uint8_t* packet, size_t packet_len, uint8_t* result) {
  uint8_t string[92] = {0};
  int string_idx = 0;
  int a, b, c = 23, d = 0, e = 0, f = 1;

  while (f < 184 && f < packet_len) {
    b = packet[f];
    f++;

    if (b <= 96) b += 32;
    b = (b - 97 - c) % 26;
    if (b < 0) b += 26;

    d *= 16;
    d += b;
    c += 17;

    if (e == 1) {
      string[string_idx++] = d;
      e = 0;
      d = 0;
    } else {
      e++;
    }
  }

  uint8_t secret_1[27] = {0};
  int idx = 0;
  for (int i = 0; i < 92; i++) {
    if ((i >= 9 && i <= 13) || (i >= 20 && i <= 41)) {
      secret_1[idx++] = string[i];
    }
  }

  int b2 = 0;
  for (int i = 0; i < 27; i++) {
    int d2 = 65;
    a = secret_1[i];

    if (a >= 97) {
      d2 += 32;
      a -= 32;
    }

    a -= 65;

    if (i == 0) {
      b2 = 3 + a;
    }

    int e2 = (a + b2) % 26;
    b2 += 2 + a;

    result[i] = e2 + d2;
  }
}

uint8_t* get_skin_compressed(tuser_data* usr) {
  user_settings* usrs = &usr->usrs;

  int skin_len = strlen(usrs->skin_code);
  uint8_t* reduced = tdarray_create(uint8_t);
  uint8_t sequence_count = 0;

  for (int i = 0; i < skin_len; i++) {
    uint8_t cg_id = get_cg_id(&usr->gdata, usrs->skin_code[i]);

    /* A run byte cannot spell 256. Flush 255 before incrementing so a
     * 256-bead solid skin becomes [255, colour], [1, colour], never [0]. */
    if (sequence_count == UINT8_MAX) {
      tdarray_push(&reduced, &sequence_count);
      tdarray_push(&reduced, &cg_id);
      sequence_count = 0;
    }
    sequence_count++;

    if (usrs->skin_code[i + 1] != usrs->skin_code[i]) {
      tdarray_push(&reduced, &sequence_count);
      tdarray_push(&reduced, &cg_id);
      sequence_count = 0;
    }
  }
  return reduced;
}

/*
 * The snake this player is steering, or nothing at all.
 *
 * Some packets name the snake they are about; the ones about you leave it
 * implied, and "implied" means the last entry — every other snake is inserted
 * at the front of the array. That holds while a match is running, but the
 * array is empty for the moments around joining and dying, and an implied
 * packet arriving in one of them used to read one element before the start of
 * the array. It found the allocator's own bookkeeping there, followed it as if
 * it were a body, and took the process down with it: the crash that sent this
 * player back to the menu a few seconds after pressing play.
 */
static snake* my_snake(game_data* gdata) {
  size_t length = tdarray_length(gdata->data.snakes);
  snake* own = length ? gdata->data.snakes + (length - 1) : NULL;
  return own && own->local_player ? own : NULL;
}


static void add_sector(game_data* gdata, int x, int y) {
  for (size_t i=0; i<tdarray_length(gdata->data.sectors); i++)
    if (gdata->data.sectors[i].x==x && gdata->data.sectors[i].y==y) return;
  struct arena_sector sector = {x,y};
  if (tdarray_length(gdata->data.sectors)<65536)
    tdarray_push(&gdata->data.sectors, &sector);
}

static void add_food(game_data* gdata, int64_t id, int cv, float x, float y,
                     float size, bool rapid, int sx, int sy) {
  food f = {.id=id, .cv=cv%NUM_COLOR_GROUPS,
    .cv2=GLM_MIN(NUM_FOOD_SIZES-1, GLM_MAX(0, (int)floorf(NUM_FOOD_SIZES*size/16.5f))),
    .xx=x, .yy=y, .rsp=rapid?3:1, .rad=1e-5f, .sz=size, .lrrad=1e-5f,
    .gfr=rand()%64, .gr=.65f+.1f*size,
    .wsp=(2*((float)rand()/RAND_MAX)-1)*.0225f, .sx=sx, .sy=sy};
  tdarray_push(&gdata->data.foods, &f);
}

static int64_t food_id(int sx, int sy, int rx, int ry) {
  return (uint32_t)sx<<24 | (uint32_t)sy<<16 | (uint32_t)rx<<8 | (uint32_t)ry;
}

/* The modern compact forms reuse the preceding packet's sector and colour.
   Older versions instead send absolute positions or an explicit 24-bit id. */
static void food_packet(game_data* g, const uint8_t* a, size_t n) {
  arena_reader r={a,n,1,true};
  int v=g->data.protocol_version, cmd=a[0], sx=0, sy=0, cv=0;
  float sector=g->data.sector_size;
  if (cmd=='F') {
    if (v>=14) { sx=arena_read(&r,1); sy=arena_read(&r,1); }
    else if (v<4) { sx=arena_read(&r,2); sy=arena_read(&r,2); }
    bool first=true;
    while (r.pos<n) {
      float x,y,size;
      int64_t id;
      if (v>=14) {
        cv=arena_read(&r,1);
        int rx=arena_read(&r,1), ry=arena_read(&r,1);
        x=sx*sector+rx*g->data.ssd256; y=sy*sector+ry*g->data.ssd256;
        size=arena_read(&r,1)/5.0f; id=food_id(sx,sy,rx,ry);
      } else if (v>=4) {
        cv=arena_read(&r,1); x=arena_read(&r,2); y=arena_read(&r,2);
        size=arena_read(&r,1)/5.0f; id=(int64_t)((double)y*g->data.grd*3+x);
        if (first) { sx=(int)floorf(x/sector); sy=(int)floorf(y/sector); }
      } else {
        id=arena_read(&r,3); cv=arena_read(&r,1);
        x=sector*(sx+arena_read(&r,1)/255.0f);
        y=sector*(sy+arena_read(&r,1)/255.0f);
        size=arena_read(&r,1)/5.0f;
      }
      if (!r.ok) return;
      add_food(g,id,cv,x,y,size,true,sx,sy);
      first=false;
    }
  } else if (cmd=='b'||cmd=='f') {
    float x,y,size;
    int64_t id;
    if (v>=14) {
      if (n-1>=5) {
        sx=arena_read(&r,1); sy=arena_read(&r,1);
        g->data.lfsx=sx; g->data.lfsy=sy;
      } else { sx=g->data.lfsx; sy=g->data.lfsy; }
      int rx=arena_read(&r,1), ry=arena_read(&r,1);
      x=sx*sector+rx*g->data.ssd256; y=sy*sector+ry*g->data.ssd256;
      id=food_id(sx,sy,rx,ry);
      if (n-1==4 || n-1==6) { cv=arena_read(&r,1); g->data.lfcv=cv; }
      else cv=g->data.lfcv;
      size=arena_read(&r,1)/5.0f;
    } else if (v>=4) {
      cv=arena_read(&r,1); x=arena_read(&r,2); y=arena_read(&r,2);
      size=arena_read(&r,1)/5.0f; id=(int64_t)((double)y*g->data.grd*3+x);
      sx=(int)floorf(x/sector); sy=(int)floorf(y/sector);
    } else {
      id=arena_read(&r,3); cv=arena_read(&r,1);
      sx=arena_read(&r,2); sy=arena_read(&r,2);
      x=sector*(sx+arena_read(&r,1)/255.0f);
      y=sector*(sy+arena_read(&r,1)/255.0f); size=arena_read(&r,1)/5.0f;
    }
    if (r.ok) add_food(g,id,cv,x,y,size,cmd=='b',sx,sy);
  } else {
    int64_t id;
    int eater=-1;
    if (v>=14) {
      if ((cmd=='<'&&n-1==4)||(cmd!='<'&&n-1==2)) {
        sx=g->data.lfvsx; sy=g->data.lfvsy;
      } else {
        sx=arena_read(&r,1); sy=arena_read(&r,1);
        g->data.lfvsx=sx; g->data.lfvsy=sy;
      }
      int rx=arena_read(&r,1), ry=arena_read(&r,1);
      id=food_id(sx,sy,rx,ry);
      if (cmd=='<') { eater=arena_read(&r,2); g->data.lfesid=eater; }
      else if (cmd=='C') eater=g->data.lfesid;
    } else {
      if (v>=4) {
        int x=arena_read(&r,2), y=arena_read(&r,2);
        id=(int64_t)((double)y*g->data.grd*3+x);
      } else id=arena_read(&r,3);
      eater=arena_read(&r,2);
    }
    if (!r.ok) return;
    int last=(int)tdarray_length(g->data.foods)-1;
    for (int i=last;i>=0;i--) if (g->data.foods[i].id==id) {
      if (eater>=0) {
        g->data.foods[i].eaten=true; g->data.foods[i].ebid=eater;
        g->data.foods[i].eaten_fr=0;
      } else {
        g->data.foods[i]=g->data.foods[last];
        tdarray_pop(g->data.foods);
      }
      break;
    }
  }
}

static void minimap_packet(game_data* g, const uint8_t* a, size_t n) {
  arena_reader r={a,n,1,true};
  int cmd=a[0], layers=1;
  if (cmd=='L') layers=arena_read(&r,1);
  int sz=cmd=='u'?80:cmd=='V'?g->data.mmsz:(int)arena_read(&r,2);
  if (sz>MAX_MINIMAP_SIZE) sz=MAX_MINIMAP_SIZE;
  if (!r.ok || sz<=0 || layers<=0) return;
  size_t bytes=MAX_MINIMAP_SIZE*MAX_MINIMAP_SIZE;
  uint8_t* staged=calloc(bytes,1);
  uint8_t* layer=calloc(bytes,1);
  uint8_t* teams=calloc(bytes,1);
  if (!staged || !layer || !teams) { free(staged); free(layer); free(teams); return; }
  if (cmd=='V') memcpy(staged,g->data.mm_data,bytes);
  for (int team=0;team<layers && r.ok;team++) {
    if (cmd=='L' && r.pos==r.size) { r.ok=false; break; }
    uint8_t* target=cmd=='L'?layer:staged;
    memset(layer,0,bytes);
    r.ok=arena_map_layer(&r,target,sz,MAX_MINIMAP_SIZE,cmd=='u',
                         cmd!='u'&&cmd!='U',cmd=='V');
    /* The source gives two-team maps distinct colours; retain their mask
       separately from the existing monochrome renderer's occupancy. */
    if (cmd=='L')
      for (int y=0;y<sz;y++) for (int x=0;x<sz;x++)
        if (layer[y*MAX_MINIMAP_SIZE+x]) {
          staged[y*MAX_MINIMAP_SIZE+x]=255;
          if (layers==2) teams[y*MAX_MINIMAP_SIZE+x]|=(uint8_t)(1u<<team);
        }
  }
  if (r.ok) {
    if (g->data.mmsz!=sz)
      memset(g->data.mm_data_follow,0,sizeof(g->data.mm_data_follow));
    g->data.mmsz=sz;
    memcpy(g->data.mm_data,staged,bytes);
    memcpy(g->data.mm_team_mask,teams,bytes);
    g->data.minimap_team_count=cmd=='L'?layers:0;
    g->data.mmgad=true;
  }
  free(teams); free(layer); free(staged);
}

static void arena_text(char* out, size_t capacity, const uint8_t* in, size_t count) {
  /* Plain text, never a format string or markup. Bounded native storage. */
  size_t size=count<capacity-1?count:capacity-1;
  for (size_t i=0;i<size;i++) out[i]=in[i]>=32?(char)in[i]:' ';
  out[size]=0;
}

static void auxiliary_packet(game_data* g, const uint8_t* a, size_t n) {
  arena_reader r={a,n,1,true};
  switch (a[0]) {
    case 'W': {
      int x=arena_read(&r,1), y=arena_read(&r,1); add_sector(g,x,y); break;
    }
    case 'S':
      g->data.session_snake_id=arena_read(&r,2);
      g->data.session_id=arena_read(&r,4); break;
    case 'm': {
      g->data.victory_score=0;
      int sct=arena_read(&r,3);
      float fam=arena_read(&r,3)/16777215.0f;
      size_t length=arena_read(&r,1);
      if (sct<(int)tdarray_length(g->data.fpsls) && g->data.fmlts[sct]>0)
        g->data.victory_score=(int)floorf((g->data.fpsls[sct]+fam/g->data.fmlts[sct]-1)*15-5);
      arena_text(g->data.victory_nick,sizeof(g->data.victory_nick),a+r.pos,length);
      r.pos+=length;
      arena_text(g->data.victory_message,sizeof(g->data.victory_message),a+r.pos,n-r.pos);
      break;
    }
    case 'o': {
      while (r.pos<n) {
        int32_t left=(int32_t)arena_read(&r,4), right=(int32_t)arena_read(&r,4);
        unsigned count=g->data.team_history_count;
        if (n==9) {
          if (count==128) {
            memmove(g->data.team_score_history,g->data.team_score_history+1,127*sizeof(g->data.team_score_history[0]));
            count=127;
          }
          g->data.team_score_history[count][0]=left;
          g->data.team_score_history[count][1]=right;
        } else {
          unsigned move=count<128?count:127;
          memmove(g->data.team_score_history+1,g->data.team_score_history,move*sizeof(g->data.team_score_history[0]));
          g->data.team_score_history[0][0]=left; g->data.team_score_history[0][1]=right;
        }
        g->data.team_history_count=count<128?count+1:128;
      }
      unsigned last=g->data.team_history_count-1;
      g->data.team_scores[0]=g->data.team_score_history[last][0];
      g->data.team_scores[1]=g->data.team_score_history[last][1];
      break;
    }
    case 'i': {
      int mode=arena_read(&r,1), id=arena_read(&r,2);
      snake* o=get_snake(g,id);
      g->data.admin_data=true;
      if (!o) break;
      if (mode==0) {
        unsigned q[4]; for(int i=0;i<4;i++) q[i]=arena_read(&r,1);
        if (q[0]||q[1]||q[2]||q[3])
          snprintf(o->admin_ip,sizeof(o->admin_ip),"%u.%u.%u.%u",q[0],q[1],q[2],q[3]);
      } else if (mode==1)
        arena_text(o->original_nickname,sizeof(o->original_nickname),a+r.pos,n-r.pos);
      break;
    }
    case 'B': {
      int id=arena_read(&r,2), x=arena_read(&r,2), y=arena_read(&r,2);
      snake* o=get_snake(g,id);
      if (o && tdarray_length(o->pts)) {
        body_part* p=o->pts+tdarray_length(o->pts)-1;
        o->point_check_mismatch=fabsf(x-p->xx)>1 || fabsf(y-p->yy)>1;
      }
      break;
    }
  }
}

void got_packet(tenv* env, uint8_t* a, int a_len) {
  tuser_data* usr = env->usr;
  tcontext* ctx = env->ctx;
  user_settings* usrs = &usr->usrs;
  game_data* gdata = &usr->gdata;
  struct mg_connection* c = gdata->connection;

  if (a_len <= 0 || !arena_packet_valid(a, (size_t)a_len, gdata->data.protocol_version)) {
    SDL_Log("Wyrm arena: ignored malformed packet (%d bytes)", a_len);
    return;
  }
  if (!gdata->arena_ready && a[0] != 'a' && a[0] != '6') return;
  gdata->last_packet_ms = SDL_GetTicks();

  char cmd = (char)a[0];
  arena_trace_in(a[0], (size_t)a_len);

  int alen = a_len;
  int plen = a_len;
  int dlen = a_len - 1;

  int m = 1;
  if (cmd == '6') {
    const arena_persona* persona = arena_persona_get(gdata->persona);
    /* From here on, a failure is evidence about this identity. Before it, a
       failure was only evidence about the socket. */
    gdata->persona_tested = true;

    /* Two clients, two answers to the same challenge. The web packet is the
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
    }

    int nick_len = strlen(usrs->nickname);
    uint8_t* ba = NULL;
    uint8_t* skin_compressed = NULL;
    int skin_compressed_len = 0;

    if (usrs->custom_skin) {
      skin_compressed = get_skin_compressed(usr);
      skin_compressed_len = tdarray_length(skin_compressed);
      ba = malloc(8 + 20 + nick_len + 8 + skin_compressed_len);
    } else {
      ba = malloc(8 + 20 + nick_len);
    }

    ba[0] = 115;
    ba[1] = 30;
    /* Version and fingerprint belong to the persona, not to the build. The two
       clients carry genuinely different twenty bytes, and sending one client's
       identity with the other's handshake is the mismatch this whole path
       exists to avoid. */
    ba[2] = persona->version >> 8 & 255;
    ba[3] = persona->version & 255;
    for (int i = 0; i < 20; i++) {
      ba[4 + i] = persona->fingerprint[i];
    }
    ba[24] = usrs->default_skin;
    ba[25] = nick_len;
    int m = 26;
    for (int i = 0; i < nick_len; i++) {
      ba[m] = (uint8_t)usrs->nickname[i];
      m++;
    }
    ba[m] = 0;
    m++;
    ba[m] = usrs->accessory;
    m++;

    if (usrs->custom_skin) {
      ba[m++] = 255;
      ba[m++] = 255;
      ba[m++] = 255;
      ba[m++] = 0;
      ba[m++] = 0;
      ba[m++] = 0;
      ba[m++] = rand() % 256;
      ba[m++] = rand() % 256;

      for (int i = 0; i < skin_compressed_len; i++) {
        ba[m] = skin_compressed[i];
        m++;
      }

      tdarray_destroy(skin_compressed);
    }

    arena_send(c, ba, m);
    free(ba);
    SDL_Log("Wyrm arena: answered the challenge as '%s' (client %u)",
            persona->name, (unsigned)persona->version);
  } else if (cmd == 'a') {
    gdata->data.grd = a[m] << 16 | a[m + 1] << 8 | a[m + 2];
    m += 3;
    int nmscps = a[m] << 8 | a[m + 1];
    m += 2;
    gdata->data.sector_size = a[m] << 8 | a[m + 1];
    gdata->data.ssd256 = gdata->data.sector_size / 256.0f;
    m += 2;
    gdata->data.sector_count_along_edge = a[m] << 8 | a[m+1];
    m += 2;
    gdata->data.spangdv = a[m] / 10.0f;
    m++;
    gdata->data.nsp1 = (a[m] << 8 | a[m + 1]) / 100.0f;
    m += 2;
    gdata->data.nsp2 = (a[m] << 8 | a[m + 1]) / 100.0f;
    m += 2;
    gdata->data.nsp3 = (a[m] << 8 | a[m + 1]) / 100.0f;
    m += 2;
    gdata->data.mamu = (a[m] << 8 | a[m + 1]) / 1e3;
    m += 2;
    gdata->data.mamu2 = (a[m] << 8 | a[m + 1]) / 1e3;
    m += 2;
    gdata->data.cst = (a[m] << 8 | a[m + 1]) / 1e3;
    m += 2;

    if (m < alen) {
      gdata->data.protocol_version = a[m];
      m++;
    }
    if (m < alen) {
      gdata->data.default_msl = a[m];
      m++;
    }

    gdata->data.real_sid = 0;
    if (m < alen) {
      gdata->data.real_sid = a[m] << 8 | a[m+1];
      m += 2;
    }

    if (m < alen) {
      gdata->data.flux_grd = a[m] << 16 | a[m + 1] << 8 | a[m + 2];
      m += 3;
    } else
      gdata->data.flux_grd = gdata->data.grd * .98;
    gdata->data.real_flux_grd = gdata->data.flux_grd;

    for (int i = 0; i < GD_FLXC; i++)
      gdata->data.flux_grds[i] = gdata->data.flux_grd;

    gdata->data.game_mode = m < alen ? a[m++] : 0;
    gdata->data.team_value = m < alen ? a[m++] : 0;
    gdata->arena_ready = true;
    gdata->rejoin_at_ms = 0;
    recalc_sep_mults(gdata);
    set_mscps(gdata, nmscps);
  } else if (cmd == 's') {
    int id = a[m] << 8 | a[m + 1];
    m += 2;

    if (dlen > 6) {
      snake o = {0};
      float ang =
          (a[m] << 16 | a[m + 1] << 8 | a[m + 2]) * 2 * PI / 16777215.0f;
      m += 3;
      int dir = a[m] - 48;
      m++;
      float wang =
          (a[m] << 16 | a[m + 1] << 8 | a[m + 2]) * 2 * PI / 16777215.0f;
      m += 3;
      float speed = (a[m] << 8 | a[m + 1]) / 1E3;
      m += 2;
      float fam = (a[m] << 16 | a[m + 1] << 8 | a[m + 2]) / 16777215.0f;
      m += 3;
      int cv = a[m];
      m++;
      float snx = (a[m] << 16 | a[m + 1] << 8 | a[m + 2]) / 5.0f;
      m += 3;
      float sny = (a[m] << 16 | a[m + 1] << 8 | a[m + 2]) / 5.0f;
      m += 3;
      int nl = a[m];
      m++;
      size_t cp_len = GLM_MIN(nl, MAX_NICKNAME_LEN);
      memcpy(o.nk, a + m, cp_len);
      o.nk[cp_len] = '\0';
      m += nl;
      int skl = gdata->data.protocol_version >= 11 ? a[m++] : 0;
      if (skl > 0) {
        // printf("TAG DATA:\n");
        // for (int unread = 0; unread < 8; unread++) {
        //   printf("[%d] = %d\n", unread, a[m + unread]);
        // }
        // printf("TAG DATA END:\n");

        for (int j = 8; j + 1 < skl; j += 2) {
          for (int i = 0; i < a[m + j]; i++) {
            if (o.cusk_len < MAX_SKIN_CODE_LEN) {
              o.cusk_data[o.cusk_len++] = a[m + j + 1];
            }
          }
        }
      }
      m += skl;
      uint8_t accessory = gdata->data.protocol_version >= 12 ? a[m++] : 255;
      float msl = gdata->data.default_msl;
      float xx = 0;
      float yy = 0;
      float lx = 0;
      float ly = 0;
      bool fp = false;
      int alen_m2 = alen - 2;

      int pts_dp_len = tdarray_length(gdata->data.pts_dp);
      body_part* pts;
      if (pts_dp_len) {
        pts = gdata->data.pts_dp[pts_dp_len - 1];
        tdarray_pop(gdata->data.pts_dp);
        tdarray_clear(pts);
      } else
        pts = tdarray_create(body_part);

      body_part po = {0};

      while (m < alen) {
        lx = xx;
        ly = yy;
        if (!fp) {
          // tail
          xx = (a[m] << 16 | a[m + 1] << 8 | a[m + 2]) / 5.0f;
          m += 3;
          yy = (a[m] << 16 | a[m + 1] << 8 | a[m + 2]) / 5.0f;
          m += 3;
          lx = xx;
          ly = yy;
          fp = true;
        } else if (m == alen_m2 && gdata->data.protocol_version >= 15) {
          // head
          float iang = a[m] << 8 | a[m + 1];
          po.iang = iang;
          m += 2;
          float ang = iang * GD_K64A;
          xx += cosf(ang) * gdata->data.default_msl;
          yy += sinf(ang) * gdata->data.default_msl;
        } else {
          // body
          xx += (a[m] - 127) / 2.0f;
          m++;
          yy += (a[m] - 127) / 2.0f;
          m++;
        }

        po.smu = 1;
        po.xx = xx;
        po.yy = yy;
        po.ltn = 1;
        po.ebx = xx - lx;
        po.eby = yy - ly;

        tdarray_push(&pts, &po);
      }

      int j = 0;
      int pts_len = tdarray_length(pts);
      float k = 1;
      for (int i = pts_len - 1; i >= 0; i--) {
        if (j < GD_SMUC_M3) {
          k = gdata->data.smus[j];
          j++;
        }
        pts[i].smu = k;
      }

      int gptz_dp_len = tdarray_length(gdata->data.gptz_dp);
      if (gptz_dp_len) {
        o.gptz = gdata->data.gptz_dp[gptz_dp_len - 1];
        tdarray_pop(gdata->data.gptz_dp);
        tdarray_clear(o.gptz);
      } else
        o.gptz = tdarray_create(gpt);

      o.pts = pts;
      if (pts) {
        o.pts = pts;
        o.sct = pts_len;
        if (pts[0].dying) o.sct--;
      };

      if (gdata->data.dead) {
        // player snake:
        o.local_player = true;
        usr->r->global.lview[0] = gdata->data.lview_xx;
        usr->r->global.lview[1] = gdata->data.lview_yy;

        gdata->data.snake_id = id;
        gdata->data.dead = false;
        android_home_begin_life();
        gdata->data.follow_view = true;
        gdata->join_spawned = true;

        gdata->data.view_xx = xx;
        gdata->data.view_yy = yy;
        gdata->data.md = false;
        gdata->data.wmd = false;

        gdata->data.lfsx = -1;
        gdata->data.lfsy = -1;
        gdata->data.lfcv = 0;
        gdata->data.lfvsx = -1;
        gdata->data.lfvsy = -1;
        gdata->data.lfesid = -1;

        /* Admission began at 'a'; visibility must not rewind send clocks. */
        gdata->join_visible = true;
        gdata->join_requires_stability = false;
        gdata->rejoin_at_ms = 0;
        gdata->conn = CONNECTED;
        gdata->life_started_sec = glfwGetTime();
        SDL_Log("Wyrm arena: spawned us (protocol %d)", gdata->data.protocol_version);
        /*
         * A different protocol number is not a reason to hang up.
         *
         * This used to close the connection the instant the snake spawned —
         * silently, because the complaint went to stdout and a phone has no
         * stdout. From the player's side it was: press Play, see the arena for
         * a quarter of a second, land back on Home with nothing said. And it
         * happened on some arenas and not others, because slither rolls its
         * servers forward a few at a time, so the number differs across the
         * fleet the picker lists.
         *
         * Refusing to play on a number we do not control means losing arenas
         * one by one as they update, for a version we have never actually been
         * broken by. So it is said out loud and play continues; if a future
         * version really does move the packets around, this line is the first
         * thing to look at.
         */
        if (gdata->data.protocol_version != PROTOCOL_VERSION) {
          SDL_Log("Wyrm arena: '%s' speaks protocol %d, we were built for %d — "
                  "playing anyway",
                  usrs->ipv4, gdata->data.protocol_version, PROTOCOL_VERSION);
        }
      }

      o.accessory = accessory;
      o.tl = o.sct + o.fam;
      o.cfl = o.tl - .6;
      o.id = id;
      o.xx = snx;
      o.yy = sny;
      o.cv = cv % NUM_DEFAULT_SKINS;
      o.cusk = skl != 0;
      o.sc = 1;
      o.ssp = gdata->data.nsp1 + gdata->data.nsp2 * o.sc;
      o.fsp = o.ssp + .1;
      o.msp = gdata->data.nsp3;
      o.ehang = ang;
      o.wehang = ang;
      o.msl = msl;
      o.ang = ang;
      o.eang = o.wang = wang;
      o.sp = o.tsp = speed;
      o.spang = o.sp / gdata->data.spangdv;
      if (o.spang > 1) o.spang = 1;
      o.fam = fam;
      o.sc = fminf(6, 1 + (o.sct - 2) / 106.0f);
      o.scang = .13 + .87 * powf((7 - o.sc) / 6.0f, 2);
      o.ssp = gdata->data.nsp1 + gdata->data.nsp2 * o.sc;
      o.fsp = o.ssp + .1;
      o.wsep = 6 * o.sc;
      float mwsep = GD_NSEP / 1;
      if (o.wsep < mwsep) o.wsep = mwsep;
      o.sep = o.wsep;
      snl(gdata, &o);
      tdarray_insert(&gdata->data.snakes, 0, &o);
    } else {
      bool is_kill = a[m] == 1;
      m++;
      int snakes_len = tdarray_length(gdata->data.snakes);
      for (int i = snakes_len - 1; i >= 0; i--) {
        snake* o = gdata->data.snakes + i;
        if (o->id == id) {
          if (o->id == gdata->data.snake_id) {
            game_capture_final_score(env);
            gdata->data.follow_view = false;
            o->id = gdata->data.snake_id = -1;
          } else
            o->id = -1234;
          if (is_kill) {
            o->dead = true;
            o->dead_amt = 0;
            o->edir = 0;
          } else {
            tdarray_push(&gdata->data.pts_dp, &o->pts);
            tdarray_push(&gdata->data.gptz_dp, &o->gptz);

            tdarray_remove(gdata->data.snakes, i);
          }
          break;
        }
      }
    }
  } else if (cmd == 'e' || cmd == 'E' || cmd == '3' || cmd == '4' ||
             cmd == '5' || cmd == 'd' || cmd == '7') {
    arena_turn update;
    if (!arena_decode_turn(a, alen, gdata->data.protocol_version, &update)) return;
    snake* o = update.own ? my_snake(gdata) : get_snake(gdata, update.id);
    bool is_my_snake = o && o == my_snake(gdata);
    if (o) {
      int dir = update.dir;
      float ang = update.ang, wang = update.wang, speed = update.speed;

      if (dir != -1) o->dir = dir;
      if (ang != -1) {
        float da = fmodf(ang - o->ang, PI2);
        if (da < 0) da += PI2;
        if (da > PI) da -= PI2;
        int k = o->fapos;
        for (int j = 0; j < GD_AFC; j++) {
          o->fas[k] -= da * gdata->data.afas[j];
          k++;
          if (k >= GD_AFC) k = 0;
        }
        o->fatg = GD_AFC;
        o->ang = ang;
      }
      if (wang != -1) {
        o->wang = wang;
        if (!is_my_snake) o->eang = wang;
      }
      if (speed != -1) {
        o->sp = speed;
        o->spang = o->sp / gdata->data.spangdv;
        if (o->spang > 1) o->spang = 1;
      }
    }
  } else if (cmd == 'h') {
    int id = a[m] << 8 | a[m + 1];
    m += 2;
    float fam = (a[m] << 16 | a[m + 1] << 8 | a[m + 2]) / 16777215.0f;
    m += 3;
    snake* o = get_snake(gdata, id);
    if (o) {
      o->fam = fam;
      snl(gdata, o);
    }
  } else if (cmd == 'r') {
    int id = a[m] << 8 | a[m + 1];
    m += 2;
    snake* o = get_snake(gdata, id);
    if (o) {
      if (dlen >= 4) {
        o->fam = (a[m] << 16 | a[m + 1] << 8 | a[m + 2]) / 16777215.0f;
        m += 3;
      }
      int pts_len = tdarray_length(o->pts);
      for (int j = 0; j < pts_len; j++)
        if (!o->pts[j].dying) {
          o->pts[j].dying = true;
          o->sct--;
          o->sc = fminf(6, 1 + (o->sct - 2) / 106.0f);
          o->scang = .13 + .87 * powf((7 - o->sc) / 6.0f, 2);
          o->ssp = gdata->data.nsp1 + gdata->data.nsp2 * o->sc;
          o->fsp = o->ssp + .1;
          o->wsep = 6 * o->sc;
          float mwsep = GD_NSEP / 1;
          if (o->wsep < mwsep) o->wsep = mwsep;
          break;
        }
      snl(gdata, o);
    }
  } else if (cmd == 'R') {
    snake* o = my_snake(gdata);
    if (o) o->rsc = a[m];
    m++;
  } else if (cmd == 'g' || cmd == 'n' || cmd == 'G' || cmd == 'N' ||
             cmd == '+' || cmd == '=') {
    bool adding_only = cmd == 'n' || cmd == 'N' || cmd == '+';
    snake* o = NULL;
    bool is_my_snake = false;
    bool own_point = gdata->data.protocol_version >= 15
        ? (cmd == 'G' || cmd == 'N' || (cmd == '=' && dlen == 6) ||
           (cmd == '+' && dlen == 9))
        : ((cmd == 'g' && dlen == 4) || (cmd == 'G' && dlen == 2) ||
           (cmd == 'n' && dlen == 7) || (cmd == 'N' && dlen == 5));
    if (own_point) {
      o = my_snake(gdata);
      is_my_snake = true;
    } else {
      int id = a[m] << 8 | a[m + 1];
      m += 2;
      o = get_snake(gdata, id);
      is_my_snake = o && o == my_snake(gdata);
    }
    /* Every branch below walks back from the last body part, so a snake with
       no body yet is as unusable here as no snake at all. */
    if (o && tdarray_length(o->pts) > 0) {
      if (adding_only)
        o->sct++;
      else {
        int pts_len = tdarray_length(o->pts);
        for (int j = 0; j < pts_len; j++)
          if (!o->pts[j].dying) {
            o->pts[j].dying = true;
            break;
          }
      }

      int pts_len = tdarray_length(o->pts);
      int lpo_i = pts_len - 1;
      float dx, dy, ox, oy, xx, yy;
      float dltn;
      float dsmu;
      float osmu;
      float d;
      body_part tmppo = {0};
      body_part* po = &tmppo;
      float msl = o->msl;
      if (gdata->data.protocol_version < 15) {
        if (gdata->data.protocol_version < 3) {
          xx = (a[m] << 16 | a[m+1] << 8 | a[m+2]) / 5.0f; m += 3;
          yy = (a[m] << 16 | a[m+1] << 8 | a[m+2]) / 5.0f; m += 3;
        } else if (cmd == 'g' || cmd == 'n') {
          xx = a[m] << 8 | a[m+1]; m += 2;
          yy = a[m] << 8 | a[m+1]; m += 2;
        } else {
          xx = o->pts[lpo_i].xx + a[m++] - 128;
          yy = o->pts[lpo_i].yy + a[m++] - 128;
        }
      } else if (cmd == '+' || cmd == '=') {
        float iang = a[m] << 8 | a[m + 1];
        po->iang = iang;
        m += 2;
        xx = a[m] << 8 | a[m + 1];
        m += 2;
        yy = a[m] << 8 | a[m + 1];
        m += 2;
      } else {
        float iang;
        if (cmd == 'G' && dlen == 2 || cmd == 'N' && dlen == 5 ||
            cmd == 'g' && dlen == 4 || cmd == 'n' && dlen == 7) {
          iang = a[m] << 8 | a[m + 1];
          m += 2;
        } else
          iang = o->pts[lpo_i].iang;

        po->iang = iang;
        float ang = iang * GD_K64A;
        xx = o->pts[lpo_i].xx + cosf(ang) * msl;
        yy = o->pts[lpo_i].yy + sinf(ang) * msl;
      }

      if (adding_only) {
        o->fam = (a[m] << 16 | a[m + 1] << 8 | a[m + 2]) / 16777215.0f;
        m += 3;
      }

      po->fpos = 0;
      po->ftg = 0;
      po->smu = 1;
      po->fsmu = 0;
      po->xx = xx;
      po->yy = yy;
      po->fx = 0;
      po->fy = 0;
      po->fltn = 0;
      po->da = 0;
      po->ltn = sqrtf(powf(po->xx - o->pts[lpo_i].xx, 2) +
                      powf(po->yy - o->pts[lpo_i].yy, 2)) /
                msl;
      po->ebx = po->xx - o->pts[lpo_i].xx;
      po->eby = po->yy - o->pts[lpo_i].yy;

      tdarray_push(&o->pts, po);
      po = o->pts + (tdarray_length(o->pts) - 1);

      if (o->iiv) {
        float hx = o->xx + o->fx;
        float hy = o->yy + o->fy;
        dx = hx - (o->pts[lpo_i].xx + o->pts[lpo_i].fx);
        dy = hy - (o->pts[lpo_i].yy + o->pts[lpo_i].fy);
        d = sqrtf(dx * dx + dy * dy);

        if (d > 1) {
          dx /= d;
          dy /= d;
        }
        float d2 = po->ltn * msl;
        float d3 = 0;
        if (d < msl)
          d3 = d;
        else
          d3 = d2;
        ox = o->pts[lpo_i].xx + o->pts[lpo_i].fx + dx * d3;
        oy = o->pts[lpo_i].yy + o->pts[lpo_i].fy + dy * d3;
        dltn = 1 - d3 / d2;
        dx = po->xx - ox;
        dy = po->yy - oy;
        int k = po->fpos;
        for (int j = 0; j < GD_EEZ; j++) {
          po->fxs[k] -= dx * gdata->data.xfas[j];
          po->fys[k] -= dy * gdata->data.xfas[j];
          po->fltns[k] -= dltn * gdata->data.xfas[j];
          k++;
          if (k >= GD_EEZ) k = 0;
        }
        po->fx = po->fxs[po->fpos];
        po->fy = po->fys[po->fpos];
        po->fltn = po->fltns[po->fpos];
        po->fsmu = po->fsmus[po->fpos];
        po->ftg = GD_EEZ;
      }
      int n2 = 3;
      pts_len = tdarray_length(o->pts);
      int k = pts_len - 3;
      int lmpo_i;
      int mpo_i;

      if (k >= 1) {
        lmpo_i = k;
        int n = 0;
        float mv = 0;
        dsmu = 0;
        for (int m = k - 1; m >= 0; m--) {
          mpo_i = m;
          n++;
          ox = o->pts[mpo_i].xx;
          oy = o->pts[mpo_i].yy;
          osmu = o->pts[mpo_i].smu;
          if (n <= 4) mv = gdata->data.cst * n / 4.0f;
          o->pts[mpo_i].xx += (o->pts[lmpo_i].xx - o->pts[mpo_i].xx) * mv;
          o->pts[mpo_i].yy += (o->pts[lmpo_i].yy - o->pts[mpo_i].yy) * mv;
          if (o->pts[mpo_i].smu != gdata->data.smus[n2]) {
            osmu = o->pts[mpo_i].smu;
            o->pts[mpo_i].smu = gdata->data.smus[n2];
            dsmu = o->pts[mpo_i].smu - osmu;
          } else
            dsmu = 0;
          if (n2 < GD_SMUC_M3) n2++;
          if (o->iiv) {
            dx = o->pts[mpo_i].xx - ox;
            dy = o->pts[mpo_i].yy - oy;
            k = o->pts[mpo_i].fpos;
            for (int j = 0; j < GD_EEZ; j++) {
              o->pts[mpo_i].fxs[k] -= dx * gdata->data.xfas[j];
              o->pts[mpo_i].fys[k] -= dy * gdata->data.xfas[j];
              o->pts[mpo_i].fsmus[k] -= dsmu * gdata->data.xfas[j];
              k++;
              if (k >= GD_EEZ) k = 0;
            }
            o->pts[mpo_i].fx = o->pts[mpo_i].fxs[o->pts[mpo_i].fpos];
            o->pts[mpo_i].fy = o->pts[mpo_i].fys[o->pts[mpo_i].fpos];
            o->pts[mpo_i].fsmu = o->pts[mpo_i].fsmus[o->pts[mpo_i].fpos];
            o->pts[mpo_i].ftg = GD_EEZ;
          }
          lmpo_i = mpo_i;
        }
      }
      o->sc = fminf(6, 1 + (o->sct - 2) / 106.0f);
      o->scang = .13 + .87 * powf((7 - o->sc) / 6.0f, 2);
      o->ssp = gdata->data.nsp1 + gdata->data.nsp2 * o->sc;
      o->fsp = o->ssp + .1;
      o->wsep = 6 * o->sc;
      float mwsep = GD_NSEP / 1;
      if (o->wsep < mwsep) o->wsep = mwsep;
      if (adding_only) snl(gdata, o);
      if (is_my_snake) {
        gdata->data.ovxx = o->xx + o->fx;
        gdata->data.ovyy = o->yy + o->fy;
      }

      float csp = o->sp * (gdata->data.etm / 8.0f) / 4.0f;
      csp *= gdata->data.lag_mult;
      float ochl = o->chl - 1;
      o->chl = csp / o->msl;
      dx = xx - o->xx;
      dy = yy - o->yy;
      float dchl = o->chl - ochl;
      o->xx = xx;
      o->yy = yy;
      k = o->fpos;
      for (int j = 0; j < GD_EEZ; j++) {
        o->fxs[k] -= dx * gdata->data.xfas[j];
        o->fys[k] -= dy * gdata->data.xfas[j];
        o->fchls[k] -= dchl * gdata->data.xfas[j];
        k++;
        if (k >= GD_EEZ) k = 0;
      }
      o->fx = o->fxs[o->fpos];
      o->fy = o->fys[o->fpos];
      o->fchl = o->fchls[o->fpos];
      o->ftg = GD_EEZ;
      if (is_my_snake) {
        float lvx = gdata->data.view_xx;
        float lvy = gdata->data.view_yy;
        if (gdata->data.follow_view) {
          gdata->data.view_xx = o->xx + o->fx;
          gdata->data.view_yy = o->yy + o->fy;
        }
        float dx = gdata->data.view_xx - gdata->data.ovxx;
        float dy = gdata->data.view_yy - gdata->data.ovyy;
        k = gdata->data.fvpos;
        for (int j = 0; j < GD_VFC; j++) {
          gdata->data.fvxs[k] -= dx * gdata->data.vfas[j];
          gdata->data.fvys[k] -= dy * gdata->data.vfas[j];
          k++;
          if (k >= GD_VFC) k = 0;
        }
        gdata->data.fvtg = GD_VFC;
      }
    }
  } else if (cmd == 'p') {
    gdata->data.wfpr = false;
    gdata->data.pings[gdata->data.cping] = gdata->data.ctm - gdata->data.last_ping_mtm;
    gdata->data.cping = (gdata->data.cping + 1) % PING_SAMPLE_COUNT;
    if (gdata->data.lagging) {
      gdata->data.etm *= gdata->data.lag_mult;
      gdata->data.lagging = false;
    }
  } else if (cmd == 'z') {
    gdata->data.real_flux_grd = a[m] << 16 | a[m + 1] << 8 | a[m + 2];
    m += 3;
    int k = gdata->data.flux_grd_pos;
    for (int j = 0; j < GD_FLXC; j++) {
      gdata->data.flux_grds[k] =
          gdata->data.flux_grds[k] +
          (gdata->data.real_flux_grd - gdata->data.flux_grds[k]) *
              gdata->data.flxas[j];
      k++;
      if (k >= GD_FLXC) k = 0;
    }
    gdata->data.flx_tg = GD_FLXC;
  } else if (cmd=='F'||cmd=='b'||cmd=='f'||cmd=='c'||cmd=='C'||cmd=='<') {
    food_packet(gdata,a,alen);
  } else if (cmd == 'w') {
    int mode = gdata->data.protocol_version >= 8 ? 2 : a[m++];
    int xx, yy;
    if (gdata->data.protocol_version >= 8) { xx=a[m++]; yy=a[m++]; }
    else { xx=a[m]<<8|a[m+1]; m+=2; yy=a[m]<<8|a[m+1]; m+=2; }
    if (mode==1) { add_sector(gdata,xx,yy); return; }
    for (int i=(int)tdarray_length(gdata->data.sectors)-1;i>=0;i--)
      if (gdata->data.sectors[i].x==xx && gdata->data.sectors[i].y==yy)
        tdarray_remove(gdata->data.sectors,i);

    int cm1 = (int)tdarray_length(gdata->data.foods) - 1;
    for (int i = cm1; i >= 0; i--) {
      food* fo = gdata->data.foods + i;
      if (fo->sx == xx)
        if (fo->sy == yy) {
          if (i != cm1) {
            gdata->data.foods[i] = gdata->data.foods[cm1];
          }
          tdarray_pop(gdata->data.foods);
          cm1--;
        }
    }
  } else if (cmd == 'j') {
    int id = a[m] << 8 | a[m + 1];
    m += 2;
    float xx = 1 + (a[m] << 8 | a[m + 1]) * 3;
    m += 2;
    float yy = 1 + (a[m] << 8 | a[m + 1]) * 3;
    m += 2;
    prey* pr = NULL;
    int preys_len = tdarray_length(gdata->data.preys);
    for (int i = preys_len - 1; i >= 0; i--) {
      if (gdata->data.preys[i].id == id) {
        pr = gdata->data.preys + i;
        break;
      }
    }
    if (pr) {
      float csp = pr->sp * (gdata->data.etm / 8) / 4;
      csp *= gdata->data.lag_mult;
      float ox = pr->xx;
      float oy = pr->yy;
      if (dlen == 15) {
        pr->dir = a[m] - 48;
        m++;
        pr->ang =
            (a[m] << 16 | a[m + 1] << 8 | a[m + 2]) * 2 * PI / 16777215.0f;
        m += 3;
        pr->wang =
            (a[m] << 16 | a[m + 1] << 8 | a[m + 2]) * 2 * PI / 16777215.0f;
        m += 3;
        pr->sp = (a[m] << 8 | a[m + 1]) / 1E3;
        m += 2;
      } else if (dlen == 11) {
        pr->ang =
            (a[m] << 16 | a[m + 1] << 8 | a[m + 2]) * 2 * PI / 16777215.0f;
        m += 3;
        pr->sp = (a[m] << 8 | a[m + 1]) / 1E3;
        m += 2;
      } else if (dlen == 12) {
        pr->dir = a[m] - 48;
        m++;
        pr->wang =
            (a[m] << 16 | a[m + 1] << 8 | a[m + 2]) * 2 * PI / 16777215.0f;
        m += 3;
        pr->sp = (a[m] << 8 | a[m + 1]) / 1E3;
        m += 2;
      } else if (dlen == 13) {
        pr->dir = a[m] - 48;
        m++;
        pr->ang =
            (a[m] << 16 | a[m + 1] << 8 | a[m + 2]) * 2 * PI / 16777215.0f;
        m += 3;
        pr->wang =
            (a[m] << 16 | a[m + 1] << 8 | a[m + 2]) * 2 * PI / 16777215.0f;
        m += 3;
      } else if (dlen == 9) {
        pr->ang =
            (a[m] << 16 | a[m + 1] << 8 | a[m + 2]) * 2 * PI / 16777215.0f;
        m += 3;
      } else if (dlen == 10) {
        pr->dir = a[m] - 48;
        m++;
        pr->wang =
            (a[m] << 16 | a[m + 1] << 8 | a[m + 2]) * 2 * PI / 16777215.0f;
        m += 3;
      } else if (dlen == 8) {
        pr->sp = (a[m] << 8 | a[m + 1]) / 1E3;
        m += 2;
      }
      pr->xx = xx + cosf(pr->ang) * csp;
      pr->yy = yy + sinf(pr->ang) * csp;
      float dx = pr->xx - ox;
      float dy = pr->yy - oy;
      int k = pr->fpos;
      for (int j = 0; j < GD_EEZ; j++) {
        pr->fxs[k] -= dx * gdata->data.xfas[j];
        pr->fys[k] -= dy * gdata->data.xfas[j];
        k++;
        if (k >= GD_EEZ) k = 0;
      }
      pr->fx = pr->fxs[pr->fpos];
      pr->fy = pr->fys[pr->fpos];
      pr->ftg = GD_EEZ;
    }
  } else if (cmd == 'y') {
    int id = a[m] << 8 | a[m + 1];
    m += 2;
    if (dlen == 2) {
      int preys_len = tdarray_length(gdata->data.preys);
      for (int i = preys_len - 1; i >= 0; i--) {
        prey* pr = gdata->data.preys + i;
        if (pr->id == id) {
          tdarray_remove(gdata->data.preys, i);
          break;
        }
      }
    }
    else if (dlen == 4) {
      int ebid = a[m] << 8 | a[m + 1];
      m += 2;
      int preys_len = tdarray_length(gdata->data.preys);
      for (int i = preys_len - 1; i >= 0; i--) {
        prey* pr = gdata->data.preys + i;
        if (pr->id == id) {
          pr->eaten = true;
          pr->ebid = ebid;
          if (get_snake(gdata, ebid))
            pr->eaten_fr = 0;
          else {
            tdarray_remove(gdata->data.preys, i);
          }
          break;
        }
      }
    } else {
      int cv = a[m];
      m++;
      float xx = (a[m] << 16 | a[m + 1] << 8 | a[m + 2]) / 5.0f;
      m += 3;
      float yy = (a[m] << 16 | a[m + 1] << 8 | a[m + 2]) / 5.0f;
      m += 3;
      float rad = a[m] / 5.0f;
      m++;
      int dir = a[m] - 48;
      m++;
      float wang =
          (a[m] << 16 | a[m + 1] << 8 | a[m + 2]) * 2 * PI / 16777215.0f;
      m += 3;
      float ang =
          (a[m] << 16 | a[m + 1] << 8 | a[m + 2]) * 2 * PI / 16777215.0f;
      m += 3;
      float speed = (a[m] << 8 | a[m + 1]) / 1E3;
      m += 2;

      tdarray_push(&gdata->data.preys, (&(prey){
        .id = id,
        .xx = xx,
        .yy = yy,
        .rad = 1e-5,
        .sz = rad,
        .cv = cv % NUM_COLOR_GROUPS,
        .dir = dir,
        .wang = wang,
        .ang = ang,
        .sp = speed,
        .gfr = rand() % 64,
        .gr = 0.5f + ((float)rand() / (float)RAND_MAX) * 0.15f + 0.1f * 6, // * rad
        .cv2 = GLM_MIN(NUM_PREY_SIZES - 1, GLM_MAX(0, (int)floorf(NUM_PREY_SIZES * rad / 9)))
      }));
    }
  } else if (cmd=='M'||cmd=='V'||cmd=='U'||cmd=='L'||cmd=='u') {
    minimap_packet(gdata,a,alen);
  } else if (cmd=='W'||cmd=='m'||cmd=='o'||cmd=='S'||cmd=='i'||cmd=='B') {
    auxiliary_packet(gdata,a,alen);
  } else if (cmd == 'l') {
    gdata->data.gotlb = true;
    memset(gdata->data.lb.entries, 0, sizeof(gdata->data.lb.entries));

    gdata->data.lb_pos = a[m];
    int pos = 0;
    m++;
    gdata->data.rank = a[m] << 8 | a[m + 1];
    m += 2;
    gdata->data.slither_count = a[m] << 8 | a[m + 1];
    m += 2;

    /*
     * The board holds ten and the packet decides how many it sends.
     *
     * Those two facts were never introduced to each other: the loop ran until
     * the packet was used up and wrote entry after entry, and `lb` is the last
     * member of `game_data`, which is followed in `tuser_data` by `usrs`, then
     * the mobile controls, then the hotkeys. So an eleventh entry did not
     * overflow into spare room — it wrote thirty-six bytes into the player's
     * settings, and enough of them walked on into the control state and then
     * off the end of the allocation entirely. That last part is what the heap
     * eventually noticed, on some other thread, freeing something unrelated:
     * `Scudo ERROR: corrupted chunk header`.
     *
     * Ten entries, and every read inside the packet.
     */
    int sct_max = (int)tdarray_length(gdata->data.fpsls) - 1;
    while (pos < NUM_LEADERBOARD_ENTRIES) {
      /* Seven bytes before the name — two of segment count, three of fill, one
         of colour, one of name length. Less than that left and the packet is
         truncated; parsing on would parse whatever the receive buffer held
         last time round. */
      if (m + 7 > alen) break;

      int sct = a[m] << 8 | a[m + 1];
      m += 2;
      float fam = (a[m] << 16 | a[m + 1] << 8 | a[m + 2]) / 16777215.0f;
      m += 3;
      int cv = a[m];
      m++;
      int nl = a[m];
      m++;
      if (m + nl > alen) break;

      /* `sct` is sixteen bits off the wire and indexes two arrays built to fit
         this server's own maximum. The two thousand entries `set_mscps` pads
         them with cover the ordinary overshoot; this covers the rest. */
      if (sct < 0) sct = 0;
      if (sct > sct_max) sct = sct_max;

      pos++;
      gdata->data.lb.entries[pos - 1].score = (int) floorf((gdata->data.fpsls[sct] + fam / gdata->data.fmlts[sct] - 1) * 15 - 5) / 1;
      gdata->data.lb.entries[pos - 1].cv = cv % 9;
      if (gdata->data.lb_pos == pos) {
        memcpy(gdata->data.lb.entries[pos - 1].nickname, usrs->nickname, MAX_NICKNAME_LEN + 1);
      } else {
        size_t cp_len = GLM_MIN(nl, MAX_NICKNAME_LEN);
        memcpy(gdata->data.lb.entries[pos - 1].nickname, a + m, cp_len);
        gdata->data.lb.entries[pos - 1].nickname[cp_len] = '\0';
      }
      m += nl;
    }
  } else if (cmd == 'k') {
    int id = a[m] << 8 | a[m+1]; m += 2;
    snake* o = get_snake(gdata, id);
    if (o) {
      o->kill_count = (uint32_t)a[m] << 16 | (uint32_t)a[m+1] << 8 | a[m+2];
      if (o == my_snake(gdata)) gdata->data.kills = (int)o->kill_count;
    }
  } else if (cmd == 'v') {
    if (a[m] == 2) {
      gdata->data.want_close_socket = true;
      gdata->data.victory_message_requested = false;
      return;
    }
    gdata->data.victory_message_requested = a[m] == 1;
    gdata->data.want_close_socket = a[m] != 1;
    gdata->data.lagging = false;
    gdata->data.lag_mult = 1;
    android_home_notify_death(env);
  }
}

void server_callback(struct mg_connection* c, int ev, void* ev_data) {
  tenv* env = c->fn_data;
  tuser_data* usr = env->usr;
  tcontext* ctx = env->ctx;
  game_data* gdata = &usr->gdata;

  /*
   * Anything said by a socket we have already moved on from.
   *
   * Leaving one arena and joining another does not stop the first socket
   * finishing. Its close arrives some frames later, by which time
   * `gdata->connection` is the new one — and every branch below used to act on
   * the game whichever socket had spoken. So the old arena's goodbye was read
   * as the new one's: a match that had barely started was already over, which
   * `retry_join` answered by joining again, and again, and then giving up and
   * going home. That is the whole of "enter, exit, enter, exit, and back to
   * Home" after picking a different server.
   *
   * `MG_EV_OPEN` is the exception. Mongoose raises it inside `mg_ws_connect`,
   * before the pointer that call returns has been stored, so the connection
   * that is about to become the current one cannot be recognised yet. It does
   * nothing to the game either way.
   */
  if (ev != MG_EV_OPEN && c != gdata->connection) {
    if (ev == MG_EV_CLOSE)
      SDL_Log("Wyrm arena: an earlier connection finished closing, ignored");
    return;
  }

  if (ev == MG_EV_OPEN) {
    printf("Connection opened\n");
  } else if (ev == MG_EV_WS_OPEN) {
    printf("Connection established\n");

    /*
     * `{1}` asks for the handshake — send nothing and the arena sends nothing
     * back, for as long as you care to wait.
     *
     * Both originals gate this on `want_etm_s`, which asks the arena to prefix
     * every message with a two-byte timing header. The web client has it off
     * and so sends this; the AIR client has it on and sends nothing here. Wyrm's
     * frame splitter does not strip such a header, so the byte goes out either
     * way and must keep going out.
     */
    arena_send(c, (uint8_t[]){1}, 1);

    /*
     * The second packet is the client describing itself, and the two originals
     * describe themselves differently.
     *
     * The web client sends `cstr` — the single character 'c' — into a buffer
     * one byte longer than it, so the zero after it is the array's own padding
     * rather than a field. The AIR client sends a real settings block: platform,
     * control scheme, and the flags its options screen offers. Each persona
     * sends what its client sends.
     *
     * Neither is optional. This was taken out for a few hours on the reasoning
     * that it did nothing — a server that works plays a full match without it —
     * and on a server that does *not* let us in, removing it turned a refusal
     * that arrived in a third of a second into one that never arrived at all:
     * the socket simply stayed open and silent until the timeout gave up. Same
     * outcome, five times the wait, and no clue on the wire.
     */
    const arena_persona* persona = arena_persona_get(gdata->persona);
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
    }
  } else if (ev == MG_EV_WS_MSG) {
    struct mg_ws_message* msg = (struct mg_ws_message*)ev_data;
    if (!msg || msg->data.len == 0) {
      game_fail_connection(gdata, "the arena sent an empty frame");
      return;
    }
    uint8_t* a = (uint8_t*)msg->data.buf;
    int m = 0;
    if (a[m] < 32) {
      int l = msg->data.len;
      while (m < l) {
        int len;
        if (a[m] < 32) {
          if (l - m < 2) {
            game_fail_connection(gdata, "the arena sent a truncated frame");
            return;
          }
          len = a[m] << 8 | a[m + 1];
          m += 2;
        } else {
          len = a[m] - 32;
          m++;
        }
        if (len <= 0 || len > l - m) {
          game_fail_connection(gdata, "the arena sent an invalid frame length");
          return;
        }
        uint8_t* a2 = a + m;
        got_packet(env, a2, len);
        m += len;
      }
    } else {
      uint8_t* a2 = a + m;
      int len = msg->data.len - m;
      got_packet(env, a2, len);
    }
  } else if (ev == MG_EV_ERROR) {
    /* Logged rather than printed: stdout goes nowhere on a phone, and this is
       the one line that says why a match ended before it began. */
    SDL_Log("Wyrm arena: '%s' errored — %s", usr->usrs.ipv4, (char*)ev_data);
    if (!gdata->closed_by_us)
      game_fail_connection(gdata, "connection error");
  } else if (ev == MG_EV_CLOSE) {
    gdata->last_life = gdata->join_spawned ? glfwGetTime() - gdata->life_started_sec : 0;
    /* The line that has to answer "why did that match end". Persona first,
       because that is the open question; then the traffic, because a client
       that went quiet, a client that flooded, and an arena that never spoke are
       three different faults which used to read identically here. */
    char traffic[320] = {0};
    arena_trace_summary(traffic, sizeof(traffic));
    SDL_Log("Wyrm arena: '%s' ended after %.1fs as '%s' — %s "
            "(snake: %s, visible: %s) [%s]",
            usr->usrs.ipv4, gdata->last_life,
            arena_persona_get(gdata->persona)->name,
            gdata->closed_by_us ? "our doing" : "the arena dropped us",
            gdata->data.follow_view ? "yes" : "never",
            gdata->join_visible ? "yes" : "no", traffic);
    /* Mongoose frees this the moment we return, so the game may not go on
       holding it. `game_close_connection` writes a byte through this pointer
       and `input()` sends its ping down it, and both were doing that to memory
       that had been handed back — the kind of damage the heap notices much
       later, on another thread, freeing something else entirely. */
    gdata->connection = NULL;
    if (gdata->arena_ready && gdata->curr_screen == PLAYING &&
        !gdata->leaving && !gdata->restart_req) {
      android_home_notify_death(env);
      game_clear_world(gdata);
      gdata->arena_ready = false;
    }
    gdata->closed = true;
  }
}
