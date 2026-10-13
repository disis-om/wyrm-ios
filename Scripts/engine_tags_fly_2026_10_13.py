"""Tags fly on death (OM, 2026-10-13).

One source for both apps (the engine_sync_2026_10_12.py pattern): Wyrm
Android's tree gets these pairs once
(`python engine_tags_fly_2026_10_13.py "<Wyrm Android>"`), and
prepare-original-engine.py applies the same pairs to the generated iOS tree.

When a snake wearing a tag dies, the tag lets go of its head and flies off:
the rope keeps its swing but stretches out to nearly three times its length,
the bobble hops as it goes (it swells and shrinks, a bounce seen from above),
and it fades out over 1.4 s. Many snakes dying at once (a rain of snakes) send
many tags flying. Drawn only on this phone; nothing on the wire.
"""

import sys
from pathlib import Path

PAIRS = {}


def pairs(relative, *items):
    PAIRS.setdefault(relative, []).extend(items)


pairs("app/src/game/tags.h",
      ("void tags_draw(tenv* env, snake* o, bool mine, bool teammate);\n",
       "void tags_draw(tenv* env, snake* o, bool mine, bool teammate);\n"
       "/* Tags that let go of a dead snake's head (OM, 2026-10-13): advanced and\n"
       "   drawn once a frame, after tags_tick. */\n"
       "void tags_draw_flying(tenv* env);\n"))

pairs("app/src/game/tags.c",
      ("""  double draw_x[ROPE_POINTS];
  double draw_y[ROPE_POINTS];
  bool draw_seeded;
} tag_slot;
""", """  double draw_x[ROPE_POINTS];
  double draw_y[ROPE_POINTS];
  bool draw_seeded;
  bool flown; /* this snake's tag has flown off (it died) */
} tag_slot;

/* A tag flying off a dead snake (OM, 2026-10-13). */
#define TAG_FLYERS 64
#define TAG_FLY_SECONDS 1.4f
typedef struct tag_flyer {
  bool used;
  int tag;
  tag_slot rope;
  float ax, ay;   /* where the rope's head end is now, world units */
  float vx, vy;   /* how fast it goes, world units a second */
  float scale;
  float age;      /* seconds since it let go */
} tag_flyer;
static tag_flyer flyers[TAG_FLYERS];
/* While a flying tag is drawn: its rope's stretch and the bobble's hop. */
static float draw_stretch = 1.0f;
static float draw_pop = 1.0f;
"""),
      ("void tags_forget_all(void) { memset(slots, 0, sizeof(slots)); }\n",
       "void tags_forget_all(void) {\n"
       "  memset(slots, 0, sizeof(slots));\n"
       "  memset(flyers, 0, sizeof(flyers));\n"
       "}\n"),
      ("""  float chain = usrs->tag_chain < 1.0f ? 1.0f : usrs->tag_chain;
""", """  float chain = usrs->tag_chain < 1.0f ? 1.0f : usrs->tag_chain;
  /* A flying tag's rope stretches (1 everywhere else). */
  chain *= draw_stretch;
"""),
      ("""  float size = TAG_SCALE * usrs->tag_scale;
""", """  float size = TAG_SCALE * usrs->tag_scale * draw_pop;
"""),
      ("""  /* Squared, because the snake's own fade is squared: a tag that faded
     linearly would still be visible over a snake that had all but gone. */
  float alpha = o->alive_amt * (1.0f - o->dead_amt);
""", """  /* Dead (OM, 2026-10-13): the tag lets go of the head and flies off on its
     own (tags_draw_flying), once; the head draws it no more. */
  if (o->dead || o->dead_amt > 0.0f) {
    if (!slot->flown && slot->seeded) tags_launch(slot, index, o->sc);
    slot->flown = true;
    return;
  }
  slot->flown = false;

  /* Squared, because the snake's own fade is squared: a tag that faded
     linearly would still be visible over a snake that had all but gone. */
  float alpha = o->alive_amt * (1.0f - o->dead_amt);
"""),
      ("""/* Tags are on (OM, 2026-10-04): the arena drops were not NTL's. 1 hides every
   tag again. */
#define WYRM_TAGS_DISABLED 0
""", """/* Tags are on (OM, 2026-10-04): the arena drops were not NTL's. 1 hides every
   tag again. */
#define WYRM_TAGS_DISABLED 0

/* A dead snake's tag lets go (OM, 2026-10-13): it takes the rope as it was
   and flies off along the rope's own direction, give or take, fast at first. */
static void tags_launch(tag_slot* slot, int tag, float scale) {
  tag_flyer* f = NULL;
  for (int i = 0; i < TAG_FLYERS && !f; ++i)
    if (!flyers[i].used) f = flyers + i;
  if (!f) {
    /* A rain of snakes: the oldest flying tag makes room. */
    f = flyers;
    for (int i = 1; i < TAG_FLYERS; ++i)
      if (flyers[i].age > f->age) f = flyers + i;
  }
  memset(f, 0, sizeof(*f));
  f->used = true;
  f->tag = tag;
  f->rope = *slot;
  f->rope.used = true;
  f->scale = scale > 0.0f ? scale : 1.0f;
  f->ax = slot->x[0];
  f->ay = slot->y[0];
  float dx = slot->x[ROPE_POINTS - 1] - slot->x[0];
  float dy = slot->y[ROPE_POINTS - 1] - slot->y[0];
  float away = (dx == 0.0f && dy == 0.0f) ? (float)(rand() % 628) / 100.0f
                                          : atan2f(dy, dx);
  away += ((float)(rand() % 1000) / 1000.0f - 0.5f) * 1.2f;
  float speed = (520.0f + (float)(rand() % 380)) * f->scale;
  f->vx = cosf(away) * speed;
  f->vy = sinf(away) * speed;
}

void tags_draw_flying(tenv* env) {
  tuser_data* usr = env->usr;
  game_data* gdata = &usr->gdata;
  if (WYRM_TAGS_DISABLED || usr->usrs.tags_hidden) return;
  if (!usr->r || !usr->r->tags_descriptor) return;
  float dt = (float)(frame_delta_ms / 1000.0);
  float zoom = gdata->data.gsc;
  for (int i = 0; i < TAG_FLYERS; ++i) {
    tag_flyer* f = flyers + i;
    if (!f->used) continue;
    f->age += dt;
    if (f->age >= TAG_FLY_SECONDS || !tags_valid(f->tag)) {
      f->used = false;
      continue;
    }
    f->ax += f->vx * dt;
    f->ay += f->vy * dt;
    float slow = powf(0.3f, dt);
    f->vx *= slow;
    f->vy *= slow;
    float grow = f->age / 0.45f;
    if (grow > 1.0f) grow = 1.0f;
    draw_stretch = 1.0f + 1.8f * grow;
    draw_pop = 1.0f + 0.45f * fabsf(sinf(f->age * 10.0f)) * expf(-f->age * 2.2f);
    float left = 1.0f - f->age / TAG_FLY_SECONDS;
    /* The rope trails behind where the tag is going. */
    float heading = atan2f(f->vy, f->vx) + (float)M_PI;
    draw_tag(env, &f->rope, TAG_TABLE + f->tag, f->ax, f->ay, heading,
             f->scale, zoom, env->ctx->size[0] * 0.5f - gdata->data.view_xx * zoom,
             env->ctx->size[1] * 0.5f - gdata->data.view_yy * zoom,
             left * left, false);
  }
  draw_stretch = 1.0f;
  draw_pop = 1.0f;
}
"""))

pairs("app/src/game/redraw.c",
      ("  tags_tick(env);\n",
       "  tags_tick(env);\n"
       "  /* Tags flying off dead snakes (OM, 2026-10-13). */\n"
       "  tags_draw_flying(env);\n"))


def apply(root, label="engine tags fly 2026-10-13", skip_applied=False):
    root = Path(root)
    for relative, items in PAIRS.items():
        target = root / relative
        text = target.read_text(encoding="utf-8")
        original = text
        crlf = "\r\n" in text
        for old, new in items:
            if crlf:
                old, new = old.replace("\n", "\r\n"), new.replace("\n", "\r\n")
            if skip_applied and new in text:
                continue
            count = text.count(old)
            if count != 1:
                raise SystemExit(f"{label}: anchor x{count} in {relative}: {old[:70]!r}")
            text = text.replace(old, new)
        if text != original:
            target.write_text(text, encoding="utf-8", newline="")
    return len(PAIRS)


if __name__ == "__main__":
    print(apply(sys.argv[1], skip_applied=True), "files written")
