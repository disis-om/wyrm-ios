#ifndef WYRM_ARENA_PROTOCOL_H
#define WYRM_ARENA_PROTOCOL_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#include <math.h>
#include <string.h>

/* Slither.txt, supplied 2026-09-07. These are source-derived, not a claim of
 * live server acceptance. Keep the decoders independent of SDL for replay tests. */
enum { ARENA_AIM_MS = 33, ARENA_TURN_MS = 50, ARENA_BOOST_MS = 50,
       ARENA_PING_MS = 250, ARENA_LAG_MS = 750, ARENA_RETRY_MS = 3333,
       ARENA_DEATH_WAIT_MS = 1600 };

typedef struct arena_reader {
  const uint8_t *bytes;
  size_t size, pos;
  bool ok;
} arena_reader;

static inline uint32_t arena_read(arena_reader *r, unsigned width) {
  if (!r->ok || width > 4 || r->pos > r->size || width > r->size-r->pos) {
    r->ok = false;
    return 0;
  }
  uint32_t v = 0;
  while (width--) v = (v << 8) | r->bytes[r->pos++];
  return v;
}

static inline float arena_lag_step(float value, bool lagging) {
  return lagging ? fmaxf(.2f, value*.85f) : fminf(1, value+.05f);
}

static inline float arena_death_step(float opacity, uint64_t elapsed,
                                    float vfr) {
  return elapsed > ARENA_DEATH_WAIT_MS ? fmaxf(0, opacity-.004f*vfr) : opacity;
}

typedef struct arena_turn {
  int id, dir;
  float ang, wang, speed;
  bool own;
} arena_turn;

static inline bool arena_decode_turn(const uint8_t *a, size_t len, int version,
                                     arena_turn *t) {
  if (!a || len<2) return false;
  char cmd = (char)a[0];
  if (!strchr("eE345d7", cmd) || cmd == 0) return false;
  arena_reader r = {a, len, 1, true};
  *t = (arena_turn){.id=-1, .dir=-1, .ang=-1, .wang=-1, .speed=-1};
  t->own = version >= 14 && (cmd=='d' || cmd=='7' || len<=3);
  if (!t->own) t->id = (int)arena_read(&r, 2);
  const float tau = 6.2831853071795864769f;
  if (version >= 6) {
    if (len == 6) {
      t->dir = cmd=='e' ? 1 : 2;
      t->ang = arena_read(&r, 1)*tau/256;
      t->wang = arena_read(&r, 1)*tau/256;
      t->speed = arena_read(&r, 1)/18.0f;
    } else if (len==5 || (version>=14 && len==3)) {
      if (cmd=='e') {
        t->ang = arena_read(&r,1)*tau/256;
        t->speed = arena_read(&r,1)/18.0f;
      } else if (cmd=='E' || cmd=='4') {
        t->dir = cmd=='E' ? 1 : 2;
        t->wang = arena_read(&r,1)*tau/256;
        t->speed = arena_read(&r,1)/18.0f;
      } else if (cmd=='3' || cmd=='5') {
        t->dir = cmd=='3' ? 1 : 2;
        t->ang = arena_read(&r,1)*tau/256;
        t->wang = arena_read(&r,1)*tau/256;
      }
    } else if (len==4 || (version>=14 && len==2)) {
      if (cmd=='e') t->ang = arena_read(&r,1)*tau/256;
      else if (cmd=='E' || cmd=='4') {
        t->dir = cmd=='E' ? 1 : 2;
        t->wang = arena_read(&r,1)*tau/256;
      } else if (cmd=='3') t->speed = arena_read(&r,1)/18.0f;
      else if (version>=14 && (cmd=='d' || cmd=='7')) {
        t->dir = cmd=='d' ? 1 : 2;
        t->ang = arena_read(&r,1)*tau/256;
        t->wang = arena_read(&r,1)*tau/256;
        t->speed = arena_read(&r,1)/18.0f;
      }
    }
  } else if (version >= 3) {
    if (cmd!='3' && (len==8 || len==7 || len==6 || len==5))
      t->dir = cmd=='e' ? 1 : 2;
    if (len==8 || len==7 || (len==5 && cmd=='3') || (len==6 && cmd=='3'))
      t->ang = arena_read(&r,2)*tau/65535;
    if (len==8 || len==7 || (len==5 && cmd!='3') || (len==6 && cmd!='3'))
      t->wang = arena_read(&r,2)*tau/65535;
    if (len==8 || len==6 || len==4) t->speed = arena_read(&r,1)/18.0f;
  } else {
    size_t d = len-1;
    if (d==11 || d==8 || d==9 || d==6) t->dir = (int)arena_read(&r,1)-48;
    if (d==11 || d==7 || d==9 || d==5) t->ang = arena_read(&r,3)*tau/16777215;
    if (d==11 || d==8 || d==9 || d==6) t->wang = arena_read(&r,3)*tau/16777215;
    if (d==11 || d==7 || d==8 || d==4) t->speed = arena_read(&r,2)/1000.0f;
  }
  return r.ok && r.pos==len;
}

/* Decode a single minimap layer; caller stages it before committing. U/u do
 * not have M/L/V's extended 255 run. Bit order is 64,32,...,1. */
static inline bool arena_map_layer(arena_reader *r, uint8_t *out, int size,
                                  int stride, bool forward, bool extended,
                                  bool toggle) {
  if (size<=0 || size>512 || stride<size) return false;
  int cell = forward ? 0 : size*size-1;
  const int step = forward ? 1 : -1;
  while (r->pos < r->size && cell>=0 && cell<size*size) {
    unsigned k = arena_read(r,1);
    if (k>=128) {
      unsigned skip = k==255 && extended ? 126*arena_read(r,1) : k-128;
      if (!r->ok) return false;
      cell += step*(int)skip;
    } else {
      for (int bit=64; bit && cell>=0 && cell<size*size; bit>>=1, cell+=step) {
        if (k & bit) {
          int index = (cell/size)*stride + cell%size;
          out[index] = toggle ? (out[index] ? 0 : 255) : 255;
        }
      }
    }
  }
  return r->ok;
}

/* Validate every byte that the retained world-update code reads. Malformed
 * packets are ignored, never made into death or a reconnect request. */
static inline bool arena_packet_valid(const uint8_t *a, size_t n, int v) {
  if (!a || !n) return false;
  size_t d=n-1, m=1;
  switch (a[0]) {
    case '6': return true;
    case 'a':
      if (n<23 || !(a[4] || a[5]) || !(a[6] || a[7])) return false;
      m=23;
      if (m<n) m++;
      if (m<n && a[m++]==0) return false;
      if (m<n) { if (n-m<2) return false; m+=2; }
      if (m<n) { if (n-m<3) return false; m+=3; }
      return true;
    case 's':
      if (d<=6) return n>=4;
      if (n<23) return false;
      m=23+(size_t)a[22];
      if (m>n) return false;
      if (v>=11) {
        if (m==n) return false;
        size_t skin=a[m++];
        if (skin>n-m) return false;
        m+=skin;
      }
      if (v>=12) { if (m==n) return false; m++; }
      return n-m>=6 && (n-m-6)%2==0;
    case 'e': case 'E': case '3': case '4': case '5': case 'd': case '7': {
      arena_turn t;
      return arena_decode_turn(a,n,v,&t);
    }
    case 'h': return n>=6;
    case 'r': return d==2 || d>=5;
    case 'R': return n>=2;
    case 'g': case 'G': case 'n': case 'N': case '+': case '=': {
      bool grow=a[0]=='n'||a[0]=='N'||a[0]=='+';
      bool own=v>=15 ? (a[0]=='G'||a[0]=='N'||(a[0]=='='&&d==6)||(a[0]=='+'&&d==9))
        : ((a[0]=='g'&&d==4)||(a[0]=='G'&&d==2)||(a[0]=='n'&&d==7)||(a[0]=='N'&&d==5));
      if (!own) m+=2;
      if (v>=15) {
        if (a[0]=='+'||a[0]=='=') m+=6;
        else if ((a[0]=='G'&&d==2)||(a[0]=='N'&&d==5)||(a[0]=='g'&&d==4)||(a[0]=='n'&&d==7)) m+=2;
      } else m+=v>=3 ? ((a[0]=='g'||a[0]=='n')?4:2) : 6;
      if (grow) m+=3;
      return m==n;
    }
    case 'F': return v>=14 ? n>=3 && (n-3)%4==0 : v>=4 ? (n-1)%6==0 : n>=5 && (n-5)%7==0;
    case 'b': case 'f': return v>=14 ? (d>=3 && d<=6) : v>=4 ? d==6 : d==11;
    case 'c': case 'C': case '<': return v>=14 ? (a[0]=='<' ? d==4||d==6 : d==2||d==4) : v>=4 ? d==6 : d==5;
    case 'W': return n>=3;
    case 'w': return n>=(v>=8?3:6);
    case 'j': return d==15||d==11||d==12||d==13||d==9||d==10||d==8;
    case 'y': return d==2||d==4||d==19;
    case 'l': return n>=6;
    case 'k': return n>=6;
    case 'v': return n>=2;
    case 'z': return n>=4;
    case 'S': return n>=7;
    case 'm': return n>=8 && (size_t)a[7]<=n-8;
    case 'o': return n>=9 && (n-1)%8==0;
    case 'i': return n>=4 && (a[1]!=0 || n>=8);
    case 'B': return n>=8;
    case 'M': case 'U': return n>=3;
    case 'L': return n>=4;
    default: return true;
  }
}
#endif
