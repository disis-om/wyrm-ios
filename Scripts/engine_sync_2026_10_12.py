"""Engine changes of 2026-10-12 (OM), taken from Vlither-android 4.7.7.

One source for both apps: Wyrm Android's engine tree gets these pairs once
(`python engine_sync_2026_10_12.py "<Wyrm Android>"`), and
prepare-original-engine.py applies the same pairs to the generated iOS tree,
so the text is identical on Android, iOS and Wyrm Desktop (which compiles the
Android tree).

  1. Ping measured like NTL: a high-resolution clock, the pong bracketed
     between the previous network poll and now (a long frame no longer reads
     as lag), the shown number updated once a second, and the worst round
     trip of the last 10 s (`ping_peak`, sent in drop reports).
  2. The network poll drains: after a poll that read something, up to three
     more 0 ms polls, so a burst queued behind a slow frame is not left for
     the next frames. Never sleeps longer than before.
  3. A lost pong no longer stops pings for the rest of the match: after 3 s
     with no answer the next ping goes out.
  4. Bot: border safety outranks every stage (an emergency turn inward,
     which also breaks a coil), the smaller of the eased and the server's
     border during a shrink, and the wall sampled around the head, not the
     camera.
  5. Arena floor changes without a hitch: the PNG decodes on a worker
     thread, the GPU upload runs on its own fence (nothing waits on it), and
     each frame in flight takes the new floor once its last use of the old
     one has finished. No vkDeviceWaitIdle any more.
  6. Arena addresses may be IPv6: `[2001:db8::1]:444`. The full address
     lives in the settings file's ext block (`ext.arena`, 64 bytes, appended)
     because the old `ipv4` field holds only 19 characters; `ipv4` keeps an
     IPv4 address as before, so older builds still read it. Every reader
     goes through user_settings_arena().
"""

import sys
from pathlib import Path

PAIRS = {}


def pairs(relative, *items):
    PAIRS.setdefault(relative, []).extend(items)


# ------------------------------------------------------------------ 1 ping

pairs("app/src/game/game_data.h",
      ("    float pings[PING_SAMPLE_COUNT];\n",
       """    float pings[PING_SAMPLE_COUNT];
    /* Ping the way NTL shows it (OM, 2026-10-12, from Vlither-android):
       game/oef.c ping_mark_*. Timed on a high-resolution clock (ctm moves once
       a frame), the shown number updated once a second, and the worst round
       trip of the last 10 s. */
    double ping_sent_ms;
    double ping_avg_stamp;
    double ping_accum_sum;
    double ping_peak_stamp;
    int ping_accum_count;
    int ping_peak;
"""),
      ("  uint64_t last_packet_ms;\n} game_data;\n",
       """  uint64_t last_packet_ms;

  /* Bytes of arena frames read so far, and when the last network poll ended
     (network/server.c): a poll that read something is followed by another,
     and a pong is timed against the end of the poll before the one that read
     it. */
  uint64_t network_rx_bytes;
  double ping_poll_end_ms;
} game_data;
"""))

pairs("app/src/game/game_data.c",
      ("  gdata->data.ping = 0;\n",
       """  gdata->data.ping = 0;
  gdata->data.ping_sent_ms = 0;
  gdata->data.ping_avg_stamp = 0;
  gdata->data.ping_accum_sum = 0;
  gdata->data.ping_accum_count = 0;
  gdata->data.ping_peak = 0;
  gdata->data.ping_peak_stamp = 0;
"""))

pairs("app/src/game/oef.h",
      ("void oef(tenv* env);\n",
       """void oef(tenv* env);

/* Ping (OM, 2026-10-12, from Vlither-android): the ping sent, the pong
   received, and the end of each frame's network poll. */
void ping_mark_sent(tenv* env);
void ping_mark_received(tenv* env);
void ping_poll_done(tenv* env);
"""))

pairs("app/src/game/oef.c",
      ("void time_step(tenv* env) {\n",
       """/* Ping (OM, 2026-10-12, from Vlither-android 4.7.7, as NTL does it). The
   arena socket is read once a frame, so a pong is seen up to a frame late,
   and a long frame (a texture, a stall) made a good network look hundreds of
   ms late. The round trip is bracketed instead: the pong was not there when
   the previous poll ended (lower bound) and is here now (upper bound).
   SDL_GetTicksNS, not glfwGetTime: Wyrm rewinds the latter. */
static double ping_clock_ms(void) { return (double)SDL_GetTicksNS() / 1e6; }

void ping_mark_sent(tenv* env) {
  env->usr->gdata.data.ping_sent_ms = ping_clock_ms();
}

void ping_poll_done(tenv* env) {
  env->usr->gdata.ping_poll_end_ms = ping_clock_ms();
}

void ping_mark_received(tenv* env) {
  game_data* gdata = &env->usr->gdata;
  /* A pong with no ping in flight (late, or after the 3 s retry): nothing
     to time. */
  if (gdata->data.ping_sent_ms <= 0) return;

  double now = ping_clock_ms();
  double sent = gdata->data.ping_sent_ms;
  gdata->data.ping_sent_ms = 0;

  double upper = now - sent;
  double lower = gdata->ping_poll_end_ms - sent;
  if (lower < 0) lower = 0;
  if (lower > upper) lower = upper;

  double est;
  if (upper - lower <= 34.0) {
    /* An ordinary frame: the middle of a window at most a frame wide. */
    est = (lower + upper) * 0.5;
  } else if (gdata->data.ping_avg_stamp > 0) {
    /* A long stall on our side: keep the last ping if it fits the window,
       else the nearest edge, so the stall does not read as lag. */
    est = (double)gdata->data.ping;
    if (est < lower) est = lower;
    if (est > upper) est = upper;
  } else {
    est = lower; /* no history yet */
  }
  int rtt = (int)(est + 0.5);
  if (rtt < 0) rtt = 0;

  /* The shown number moves once a second (NTL), from the samples since. */
  gdata->data.ping_accum_sum += rtt;
  gdata->data.ping_accum_count++;
  if (now - gdata->data.ping_avg_stamp > 1000) {
    int avg = (int)(gdata->data.ping_accum_sum / gdata->data.ping_accum_count + 0.5);
    gdata->data.ping = gdata->data.ping_avg_stamp > 0
                           ? (gdata->data.ping + avg) / 2
                           : avg;
    gdata->data.ping_avg_stamp = now;
    gdata->data.ping_accum_sum = 0;
    gdata->data.ping_accum_count = 0;
  }

  /* The worst round trip inside a 10 s window (NTL's peak). */
  if (now - gdata->data.ping_peak_stamp > 10000) {
    gdata->data.ping_peak = rtt;
    gdata->data.ping_peak_stamp = now;
  } else if (rtt > gdata->data.ping_peak) {
    gdata->data.ping_peak = rtt;
  }
}

void time_step(tenv* env) {
"""),
      ("""  if (gdata->data.lagging) {
    gdata->data.lag_mult = arena_lag_step(gdata->data.lag_mult, true);
""",
       """  /* 3 (OM, 2026-10-12, from Vlither-android): a lost pong left `wfpr` set
     for good, and input() never pinged again; on mobile data a silent socket
     is what a carrier's NAT drops. After 3 s (four times the 750 ms lag mark)
     the next ping goes out; a pong for the lost one is not timed. */
  if (gdata->data.wfpr && gdata->data.ctm - gdata->data.last_ping_mtm > 3000) {
    gdata->data.wfpr = false;
    gdata->data.ping_sent_ms = 0;
  }

  if (gdata->data.lagging) {
    gdata->data.lag_mult = arena_lag_step(gdata->data.lag_mult, true);
"""))

pairs("app/src/game/input.c",
      ('#include "../network/arena_protocol.h"\n',
       '#include "../network/arena_protocol.h"\n#include "oef.h"\n'),
      ("""      gdata->data.wfpr = true;
      arena_send(connection, (uint8_t[]){gdata->data.protocol_version >= 5 ? 251 : 112}, 1);
""",
       """      gdata->data.wfpr = true;
      ping_mark_sent(env);
      arena_send(connection, (uint8_t[]){gdata->data.protocol_version >= 5 ? 251 : 112}, 1);
"""))

pairs("app/src/network/callback.c",
      ('#include "../game/tags.h"\n',
       '#include "../game/tags.h"\n#include "../game/oef.h"\n'),
      ("""    gdata->data.pings[gdata->data.cping] = gdata->data.ctm - gdata->data.last_ping_mtm;
    gdata->data.cping = (gdata->data.cping + 1) % PING_SAMPLE_COUNT;
""",
       """    ping_mark_received(env);
"""),
      ("""      game_fail_connection(gdata, "the arena sent an empty frame");
      return;
    }
""",
       """      game_fail_connection(gdata, "the arena sent an empty frame");
      return;
    }
    gdata->network_rx_bytes += msg->data.len;
"""))

pairs("app/src/game/redraw.c",
      ("""  // ping calc
  float sum = 0;
  for (int i = 0; i < PING_SAMPLE_COUNT; i++) {
    sum += gdata->data.pings[i];
  }
  sum /= PING_SAMPLE_COUNT;

  gdata->data.ping_follow = glm_lerp(gdata->data.ping_follow,
                                     GLM_MAX(GOOD_PING, GLM_MIN(sum, BAD_PING)),
                                     0.1f * gdata->data.vfr);

  if (gdata->data.cping == PING_SAMPLE_COUNT - 1) {
    gdata->data.ping = (int)roundf(sum);
  }
""",
       """  // ping: measured per pong in oef.c (ping_mark_received, OM 2026-10-12);
  // this only eases the colour towards it.
  gdata->data.ping_follow = glm_lerp(
      gdata->data.ping_follow,
      GLM_MAX(GOOD_PING, GLM_MIN((float)gdata->data.ping, BAD_PING)),
      0.1f * gdata->data.vfr);
"""))

# ------------------------------------------------------------- 2 the drain

pairs("app/src/network/server.c",
      ("void server_poll(tenv* env) {\n",
       """/* 2 (OM, 2026-10-12, from Vlither-android): Mongoose reads a socket once a
   poll, so a burst the arena queued behind a slow frame waited for the next
   frames. After a poll that read something, up to three more 0 ms polls
   catch up; an idle socket costs one poll as before, and nothing sleeps
   longer than before. Then the poll's end is noted for the ping. */
static void server_poll_drain(tenv* env, int first_wait_ms) {
  game_data* gdata = &env->usr->gdata;
  uint64_t before = gdata->network_rx_bytes;
  mg_mgr_poll(&gdata->network_manager, first_wait_ms);
  for (int pass = 1; pass < 4; ++pass) {
    if (!gdata->connection || gdata->closed) break;
    if (gdata->network_rx_bytes == before) break;
    before = gdata->network_rx_bytes;
    mg_mgr_poll(&gdata->network_manager, 0);
  }
  ping_poll_done(env);
}

void server_poll(tenv* env) {
"""),
      ("  mg_mgr_poll(&gdata->network_manager, wait_ms);\n",
       "  server_poll_drain(env, wait_ms);\n"),
      ("#else\n  mg_mgr_poll(&gdata->network_manager, 0);\n#endif\n}\n",
       "#else\n  server_poll_drain(env, 0);\n#endif\n}\n"),
      ('#include "arena_trace.h"\n',
       '#include "arena_trace.h"\n#include "../game/oef.h"\n'))

# ------------------------------------------------------------------ 4 bot

pairs("app/src/game/sbot.c",
      ("""static inline float dist2(float ax, float ay, float bx, float by) {
  float dx = ax - bx, dy = ay - by;
  return dx * dx + dy * dy;
}
""",
       """static inline float dist2(float ax, float ay, float bx, float by) {
  float dx = ax - bx, dy = ay - by;
  return dx * dx + dy * dy;
}

/* During a shrink the renderer eases flux_grd over several frames, but the
   server's border (real_flux_grd) has already moved: the bot obeys the smaller
   (OM, 2026-10-12, from Vlither-android). */
static inline float safe_border_radius(const game_data* gdata) {
  float smoothed = gdata->data.flux_grd;
  float server = gdata->data.real_flux_grd;
  if (server > 0.0f && (smoothed <= 0.0f || server < smoothed)) return server;
  return smoothed;
}
"""),
      ("""  float view_ang = atan2f(gdata->data.view_yy - gdata->data.grd,
                          gdata->data.view_xx - gdata->data.grd);
  float dist_to_ctr = sqrtf(dist2(B.x, B.y, gdata->data.grd, gdata->data.grd));
  bool near_wall = (gdata->data.flux_grd - dist_to_ctr) < 1000.0f;

  if (near_wall) {
    float bpw = BORDER_PT_RADIUS * 2.0f;
    float brad = gdata->data.flux_grd + BORDER_PT_RADIUS;
    for (int k = -3; k <= 3; k++) {
      float wa = view_ang + (k * bpw) / gdata->data.flux_grd;
""",
       """  /* The head itself, not the eased camera: camera lag put the sampled wall
     arc beside the real danger. A wider arc (12 points each side). */
  float view_ang = atan2f(B.y - gdata->data.grd, B.x - gdata->data.grd);
  float dist_to_ctr = sqrtf(dist2(B.x, B.y, gdata->data.grd, gdata->data.grd));
  float border_radius = safe_border_radius(gdata);
  bool near_wall = border_radius > 0.0f &&
                   (border_radius - dist_to_ctr) < 1000.0f;

  if (near_wall) {
    float bpw = BORDER_PT_RADIUS * 2.0f;
    float brad = border_radius + BORDER_PT_RADIUS;
    for (int k = -12; k <= 12; k++) {
      float wa = view_ang + (k * bpw) / border_radius;
"""),
      ("""  float dist_to_ctr = sqrtf(dist2(B.x, B.y, gdata->data.grd, gdata->data.grd));
  bool near_wall = (gdata->data.flux_grd - dist_to_ctr) < 1000.0f;
  float wall_od = 0.0f;

  if (near_wall) {
    float view_ang = atan2f(gdata->data.view_yy - gdata->data.grd,
                            gdata->data.view_xx - gdata->data.grd);
    float bpw = BORDER_PT_RADIUS * 2.0f;
    float brad = gdata->data.flux_grd + BORDER_PT_RADIUS;
""",
       """  float dist_to_ctr = sqrtf(dist2(B.x, B.y, gdata->data.grd, gdata->data.grd));
  float border_radius = safe_border_radius(gdata);
  bool near_wall = border_radius > 0.0f &&
                   (border_radius - dist_to_ctr) < 1000.0f;
  float wall_od = 0.0f;

  if (near_wall) {
    float view_ang = atan2f(B.y - gdata->data.grd, B.x - gdata->data.grd);
    float bpw = BORDER_PT_RADIUS * 2.0f;
    float brad = border_radius + BORDER_PT_RADIUS;
"""),
      ("""    for (int k = -2; k <= 2; k++) {
      float wa = view_ang + (k * bpw) / gdata->data.flux_grd;
""",
       """    for (int k = -2; k <= 2; k++) {
      float wa = view_ang + (k * bpw) / border_radius;
"""),
      ("""void sbot_go(tenv* env) {
""",
       """/* Border safety outranks every stage (OM, 2026-10-12, from Vlither-android):
   check_collision() ran only outside self-circle stage 2, so a coiling snake
   could follow its own body into the wall. This predictive guard breaks the
   food or coil state early and turns towards a safe point inward. */
static bool avoid_border_emergency(game_data* gdata) {
  const float border_radius = safe_border_radius(gdata);
  const float center = gdata->data.grd;
  if (border_radius <= 0.0f || center <= 0.0f) return false;

  float dx = B.x - center;
  float dy = B.y - center;
  float dist = sqrtf(dx * dx + dy * dy);
  if (dist < 1.0f) return false;

  float outward_x = dx / dist;
  float outward_y = dy / dist;
  float clearance = border_radius - dist - B.radius;
  float guard = fmaxf(700.0f, B.head_circle.r + B.width * (4.0f + B.speed_mult));
  float lookahead = fmaxf(500.0f, B.width * (5.0f + 2.0f * B.speed_mult));
  float predicted_x = B.x + B.ca * lookahead;
  float predicted_y = B.y + B.sa * lookahead;
  float predicted_dist = sqrtf(dist2(predicted_x, predicted_y, center, center));
  float predicted_clearance = border_radius - predicted_dist - B.radius;
  float outward_heading = B.ca * outward_x + B.sa * outward_y;

  bool imminent = clearance <= guard * 0.45f ||
                  predicted_clearance <= guard * 0.70f;
  bool unsafe_course = clearance <= guard &&
                       (outward_heading > -0.25f || B.stage == 2);
  if (!imminent && !unsafe_course) return false;

  float retreat = fmaxf(1000.0f, guard * 1.75f);
  B.goal = (v2){roundf(B.x - outward_x * retreat),
                roundf(B.y - outward_y * retreat)};
  B.stage = 0;
  B.has_food = false;
  B.delay_frame = -1;
  gdata->bot.output.accel = false;
  return true;
}

void sbot_go(tenv* env) {
"""),
      ("""  if (B.stage == 2) {
    bot->output.accel = (bool)B.default_accel;
    follow_circle_self(gdata);
""",
       """  if (avoid_border_emergency(gdata)) {
    /* The emergency goal is set; no delayed food or circle action may
       replace it this frame. */
  } else if (B.stage == 2) {
    bot->output.accel = (bool)B.default_accel;
    follow_circle_self(gdata);
"""),
      ("""  if (B.stage == 2) {
    gdata->bot.output.accel = (bool)B.default_accel;
    follow_circle_self(gdata);
""",
       """  if (avoid_border_emergency(gdata)) {
    /* The AI arena's bots obey the same border guard. */
  } else if (B.stage == 2) {
    gdata->bot.output.accel = (bool)B.default_accel;
    follow_circle_self(gdata);
"""))


# ------------------------------------------------- 5 floor upload, async

ASYNC_UPLOAD_C = r'''/* A texture uploading in the background (OM, 2026-10-12, from
   Vlither-android): the same copy and mip chain as create_mipmap_texture(),
   recorded on a command buffer of its own and submitted on a fence of its
   own, so nothing waits on the GPU. texture_upload_poll() finishes it once
   the fence has signalled. Engine thread only (the command pool and the
   queue are the frame's). */
struct texture_upload {
  texture* tex;
  VkBuffer staging;
  VmaAllocation staging_memory;
  VkCommandBuffer cmd;
  VkFence fence;
  int mip_levels;
};

static void texture_upload_release(tcontext* ctx, texture_upload* up) {
  if (up->cmd) vkFreeCommandBuffers(ctx->device, ctx->cmd_pool, 1, &up->cmd);
  if (up->fence) vkDestroyFence(ctx->device, up->fence, NULL);
  if (up->staging) vmaDestroyBuffer(ctx->allocator, up->staging, up->staging_memory);
  free(up);
}

static void texture_upload_drop_image(tcontext* ctx, texture_upload* up) {
  if (up->tex) {
    if (up->tex->image) vmaDestroyImage(ctx->allocator, up->tex->image, up->tex->memory);
    free(up->tex);
    up->tex = NULL;
  }
}

static void texture_barrier(VkCommandBuffer cmd, VkImage image, int level,
                            int levels, VkImageLayout from, VkImageLayout to,
                            VkAccessFlags src, VkAccessFlags dst,
                            VkPipelineStageFlags src_stage,
                            VkPipelineStageFlags dst_stage) {
  vkCmdPipelineBarrier(
      cmd, src_stage, dst_stage, 0, 0, NULL, 0, NULL, 1,
      &(VkImageMemoryBarrier){
          .sType = VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER,
          .srcAccessMask = src,
          .dstAccessMask = dst,
          .oldLayout = from,
          .newLayout = to,
          .srcQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED,
          .dstQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED,
          .image = image,
          .subresourceRange = {.aspectMask = VK_IMAGE_ASPECT_COLOR_BIT,
                               .baseMipLevel = level,
                               .levelCount = levels,
                               .baseArrayLayer = 0,
                               .layerCount = 1}});
}

texture_upload* texture_upload_begin(tcontext* ctx, const unsigned char* rgba,
                                     int w, int h) {
  if (!ctx || !rgba || w <= 0 || h <= 0) return NULL;
  VkPhysicalDeviceProperties gpu = {0};
  vkGetPhysicalDeviceProperties(ctx->ph_device, &gpu);
  if ((uint32_t)w > gpu.limits.maxImageDimension2D ||
      (uint32_t)h > gpu.limits.maxImageDimension2D) {
    SDL_Log("Wyrm texture: %d x %d is over this GPU's %u px", w, h,
            gpu.limits.maxImageDimension2D);
    return NULL;
  }
  /* As create_mipmap_texture(): no mip blits on Mali, nor where the format
     cannot be blitted. */
  int mip_levels = (int)(floorf(log2f((float)GLM_MAX(w, h))) + 1);
  if (strstr(gpu.deviceName, "Mali") != NULL) mip_levels = 1;
  if (mip_levels > 1) {
    VkFormatProperties format = {0};
    vkGetPhysicalDeviceFormatProperties(ctx->ph_device, VK_FORMAT_R8G8B8A8_UNORM,
                                        &format);
    const VkFormatFeatureFlags need = VK_FORMAT_FEATURE_BLIT_SRC_BIT |
                                      VK_FORMAT_FEATURE_BLIT_DST_BIT |
                                      VK_FORMAT_FEATURE_SAMPLED_IMAGE_FILTER_LINEAR_BIT;
    if ((format.optimalTilingFeatures & need) != need) mip_levels = 1;
  }

  texture_upload* up = calloc(1, sizeof(*up));
  if (!up) return NULL;
  up->tex = calloc(1, sizeof(texture));
  if (!up->tex) { free(up); return NULL; }
  up->mip_levels = mip_levels;

  const VkDeviceSize bytes = (VkDeviceSize)w * (VkDeviceSize)h * 4;
  VmaAllocationInfo info = {0};
  if (vmaCreateBuffer(
          ctx->allocator,
          &(VkBufferCreateInfo){.sType = VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO,
                                .size = bytes,
                                .usage = VK_BUFFER_USAGE_TRANSFER_SRC_BIT,
                                .sharingMode = VK_SHARING_MODE_EXCLUSIVE},
          &(VmaAllocationCreateInfo){
              .flags = VMA_ALLOCATION_CREATE_HOST_ACCESS_SEQUENTIAL_WRITE_BIT |
                       VMA_ALLOCATION_CREATE_MAPPED_BIT,
              .usage = VMA_MEMORY_USAGE_AUTO},
          &up->staging, &up->staging_memory, &info) != VK_SUCCESS ||
      !info.pMappedData) {
    up->staging = VK_NULL_HANDLE;
    texture_upload_drop_image(ctx, up);
    texture_upload_release(ctx, up);
    return NULL;
  }
  memcpy(info.pMappedData, rgba, (size_t)bytes);
  vmaFlushAllocation(ctx->allocator, up->staging_memory, 0, bytes);

  texture* t = up->tex;
  if (vmaCreateImage(
          ctx->allocator,
          &(VkImageCreateInfo){
              .sType = VK_STRUCTURE_TYPE_IMAGE_CREATE_INFO,
              .imageType = VK_IMAGE_TYPE_2D,
              .format = VK_FORMAT_R8G8B8A8_UNORM,
              .extent = {w, h, 1},
              .mipLevels = mip_levels,
              .arrayLayers = 1,
              .samples = VK_SAMPLE_COUNT_1_BIT,
              .tiling = VK_IMAGE_TILING_OPTIMAL,
              .usage = VK_IMAGE_USAGE_TRANSFER_DST_BIT | VK_IMAGE_USAGE_SAMPLED_BIT |
                       (mip_levels > 1 ? VK_IMAGE_USAGE_TRANSFER_SRC_BIT : 0),
              .sharingMode = VK_SHARING_MODE_EXCLUSIVE,
              .initialLayout = VK_IMAGE_LAYOUT_UNDEFINED},
          &(VmaAllocationCreateInfo){.usage = VMA_MEMORY_USAGE_AUTO, .priority = 1.0f},
          &t->image, &t->memory, NULL) != VK_SUCCESS) {
    t->image = VK_NULL_HANDLE;
    texture_upload_drop_image(ctx, up);
    texture_upload_release(ctx, up);
    return NULL;
  }
  t->size[0] = w;
  t->size[1] = h;

  if (vkAllocateCommandBuffers(
          ctx->device,
          &(VkCommandBufferAllocateInfo){
              .sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO,
              .commandPool = ctx->cmd_pool,
              .level = VK_COMMAND_BUFFER_LEVEL_PRIMARY,
              .commandBufferCount = 1},
          &up->cmd) != VK_SUCCESS ||
      vkCreateFence(ctx->device,
                    &(VkFenceCreateInfo){.sType = VK_STRUCTURE_TYPE_FENCE_CREATE_INFO},
                    NULL, &up->fence) != VK_SUCCESS) {
    texture_upload_drop_image(ctx, up);
    texture_upload_release(ctx, up);
    return NULL;
  }

  VkCommandBuffer cmd = up->cmd;
  vkBeginCommandBuffer(cmd, &(VkCommandBufferBeginInfo){
                                .sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO,
                                .flags = VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT});
  texture_barrier(cmd, t->image, 0, 1, VK_IMAGE_LAYOUT_UNDEFINED,
                  VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL, VK_ACCESS_NONE,
                  VK_ACCESS_TRANSFER_WRITE_BIT, VK_PIPELINE_STAGE_TOP_OF_PIPE_BIT,
                  VK_PIPELINE_STAGE_TRANSFER_BIT);
  vkCmdCopyBufferToImage(
      cmd, up->staging, t->image, VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL, 1,
      &(VkBufferImageCopy){
          .imageSubresource = {.aspectMask = VK_IMAGE_ASPECT_COLOR_BIT,
                               .mipLevel = 0,
                               .baseArrayLayer = 0,
                               .layerCount = 1},
          .imageExtent = {w, h, 1}});
  if (mip_levels > 1) {
    texture_barrier(cmd, t->image, 0, 1, VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL,
                    VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL,
                    VK_ACCESS_TRANSFER_WRITE_BIT, VK_ACCESS_TRANSFER_READ_BIT,
                    VK_PIPELINE_STAGE_TRANSFER_BIT, VK_PIPELINE_STAGE_TRANSFER_BIT);
    for (int i = 1; i < mip_levels; i++) {
      texture_barrier(cmd, t->image, i, 1, VK_IMAGE_LAYOUT_UNDEFINED,
                      VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL, VK_ACCESS_NONE,
                      VK_ACCESS_TRANSFER_WRITE_BIT, VK_PIPELINE_STAGE_TRANSFER_BIT,
                      VK_PIPELINE_STAGE_TRANSFER_BIT);
      const int32_t src_w = GLM_MAX(1, w >> (i - 1));
      const int32_t src_h = GLM_MAX(1, h >> (i - 1));
      const int32_t dst_w = GLM_MAX(1, w >> i);
      const int32_t dst_h = GLM_MAX(1, h >> i);
      vkCmdBlitImage(cmd, t->image, VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL,
                     t->image, VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL, 1,
                     &(VkImageBlit){
                         .srcSubresource = {VK_IMAGE_ASPECT_COLOR_BIT, i - 1, 0, 1},
                         .srcOffsets = {{0, 0, 0}, {src_w, src_h, 1}},
                         .dstSubresource = {VK_IMAGE_ASPECT_COLOR_BIT, i, 0, 1},
                         .dstOffsets = {{0, 0, 0}, {dst_w, dst_h, 1}}},
                     VK_FILTER_LINEAR);
      texture_barrier(cmd, t->image, i, 1, VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL,
                      VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL,
                      VK_ACCESS_TRANSFER_WRITE_BIT, VK_ACCESS_TRANSFER_READ_BIT,
                      VK_PIPELINE_STAGE_TRANSFER_BIT, VK_PIPELINE_STAGE_TRANSFER_BIT);
    }
    texture_barrier(cmd, t->image, 0, mip_levels,
                    VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL,
                    VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL,
                    VK_ACCESS_TRANSFER_READ_BIT, VK_ACCESS_SHADER_READ_BIT,
                    VK_PIPELINE_STAGE_TRANSFER_BIT,
                    VK_PIPELINE_STAGE_FRAGMENT_SHADER_BIT);
  } else {
    texture_barrier(cmd, t->image, 0, 1, VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL,
                    VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL,
                    VK_ACCESS_TRANSFER_WRITE_BIT, VK_ACCESS_SHADER_READ_BIT,
                    VK_PIPELINE_STAGE_TRANSFER_BIT,
                    VK_PIPELINE_STAGE_FRAGMENT_SHADER_BIT);
  }
  if (vkEndCommandBuffer(cmd) != VK_SUCCESS ||
      vkQueueSubmit(ctx->queue, 1,
                    &(VkSubmitInfo){.sType = VK_STRUCTURE_TYPE_SUBMIT_INFO,
                                    .commandBufferCount = 1,
                                    .pCommandBuffers = &cmd},
                    up->fence) != VK_SUCCESS) {
    texture_upload_drop_image(ctx, up);
    texture_upload_release(ctx, up);
    return NULL;
  }
  return up;
}

bool texture_upload_poll(tcontext* ctx, texture_upload* up, texture** out) {
  *out = NULL;
  VkResult status = vkGetFenceStatus(ctx->device, up->fence);
  if (status == VK_NOT_READY) return false;
  if (status == VK_SUCCESS &&
      vkCreateImageView(
          ctx->device,
          &(VkImageViewCreateInfo){
              .sType = VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO,
              .image = up->tex->image,
              .viewType = VK_IMAGE_VIEW_TYPE_2D,
              .format = VK_FORMAT_R8G8B8A8_UNORM,
              .components = {VK_COMPONENT_SWIZZLE_IDENTITY, VK_COMPONENT_SWIZZLE_IDENTITY,
                             VK_COMPONENT_SWIZZLE_IDENTITY, VK_COMPONENT_SWIZZLE_IDENTITY},
              .subresourceRange = {.aspectMask = VK_IMAGE_ASPECT_COLOR_BIT,
                                   .baseMipLevel = 0,
                                   .levelCount = up->mip_levels,
                                   .baseArrayLayer = 0,
                                   .layerCount = 1}},
          NULL, &up->tex->view) == VK_SUCCESS) {
    *out = up->tex;
    up->tex = NULL;
  } else {
    SDL_Log("Wyrm texture: background upload failed (Vulkan result %d)", status);
    texture_upload_drop_image(ctx, up);
  }
  texture_upload_release(ctx, up);
  return true;
}

void texture_upload_cancel(tcontext* ctx, texture_upload* up) {
  if (!up) return;
  vkWaitForFences(ctx->device, 1, &up->fence, VK_TRUE, UINT64_MAX);
  texture_upload_drop_image(ctx, up);
  texture_upload_release(ctx, up);
}

texture* create_minimap_texture(tcontext* ctx, int width) {
'''

pairs("app/src/rendering/texture.h",
      ("void destroy_texture(tcontext* ctx, texture* tex);\n",
       """void destroy_texture(tcontext* ctx, texture* tex);

/* A texture uploading in the background (OM, 2026-10-12): begin copies the
   pixels and returns at once (NULL when it cannot start); poll returns true
   once the GPU has finished, with the texture in *out (NULL if it failed);
   cancel waits for it and throws it away. */
typedef struct texture_upload texture_upload;
texture_upload* texture_upload_begin(tcontext* ctx, const unsigned char* rgba,
                                     int w, int h);
bool texture_upload_poll(tcontext* ctx, texture_upload* up, texture** out);
void texture_upload_cancel(tcontext* ctx, texture_upload* up);
"""))

pairs("app/src/rendering/texture.c",
      ("texture* create_minimap_texture(tcontext* ctx, int width) {\n",
       ASYNC_UPLOAD_C))

pairs("app/src/rendering/renderer.h",
      ("  texture* bg_tex;\n  int background;\n",
       """  texture* bg_tex;
  int background;
  /* An arena floor change in progress (OM, 2026-10-12): renderer.c. */
  struct bg_swap* bg_swap;
"""))

BG_SWAP_C = r'''/* 5 (OM, 2026-10-12, from Vlither-android): the arena floor changes without
   a hitch. The PNG decodes on a worker thread, the GPU copy runs on its own
   fence (texture_upload_*), and each frame in flight takes the new floor in
   its descriptor set once its last use of the old one has finished: the
   current frame (its fence was waited in tcontext_begin) or any frame whose
   fence has signalled. The old floor is freed once every frame that could
   still read it has been waited for. Before, the whole thing ran on the
   engine thread and ended in vkDeviceWaitIdle. Driven by renderer_render(),
   so a floor chosen while nothing is drawn applies with the next frame. */
static void renderer_set_background_now(renderer* r, tcontext* ctx, int index);

typedef struct bg_swap {
  int want;              /* the floor asked for last */
  int job;               /* the floor being decoded or uploaded, -1 none */
  SDL_Thread* thread;
  SDL_AtomicInt decoded; /* 1 once the worker has finished */
  char path[512];
  unsigned char* pixels;
  int w, h;
  texture_upload* upload;
  texture* ready;        /* uploaded, being bound frame by frame */
  int ready_index;
  uint32_t bound;        /* frames whose set already shows `ready` */
  texture* retired;      /* the old floor, until no frame can read it */
  int retire_after;      /* renders left before it is freed */
} bg_swap;

static int bg_swap_decode(void* data) {
  bg_swap* s = data;
  int channels = 0;
  s->pixels = stbi_load(s->path, &s->w, &s->h, &channels, 4);
  SDL_SetAtomicInt(&s->decoded, 1);
  return 0;
}

static void renderer_bind_background(renderer* r, tcontext* ctx, int frame,
                                     texture* tex) {
  vkUpdateDescriptorSets(
      ctx->device, 1,
      (VkWriteDescriptorSet[]){
          {
              .sType = VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET,
              .dstSet = r->global_set[frame],
              .dstBinding = 2,
              .dstArrayElement = 0,
              .descriptorCount = 1,
              .descriptorType = VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER,
              .pImageInfo =
                  &(VkDescriptorImageInfo){r->linear_sampler, tex->view,
                                           VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL},
          },
      },
      0, NULL);
}

static void renderer_bg_swap_step(renderer* r, tcontext* ctx) {
  bg_swap* s = r->bg_swap;
  int cur = ctx->current_frame;
  int fif = ctx->fif < 32 ? ctx->fif : 32;
  uint32_t all = fif >= 32 ? 0xFFFFFFFFu : ((1u << fif) - 1u);

  if (s->retired && --s->retire_after <= 0) {
    destroy_texture(ctx, s->retired);
    s->retired = NULL;
  }

  if (s->ready) {
    for (int i = 0; i < fif; ++i) {
      if (s->bound & (1u << i)) continue;
      if (i != cur &&
          vkGetFenceStatus(ctx->device, ctx->frames[i].wait_fence) != VK_SUCCESS)
        continue;
      renderer_bind_background(r, ctx, i, s->ready);
      s->bound |= 1u << i;
    }
    if ((s->bound & all) == all) {
      s->retired = r->bg_tex;
      s->retire_after = fif + 1;
      r->bg_tex = s->ready;
      r->background = s->ready_index;
      s->ready = NULL;
      s->bound = 0;
    }
  } else if (s->upload) {
    texture* done = NULL;
    if (texture_upload_poll(ctx, s->upload, &done)) {
      s->upload = NULL;
      if (done && s->job == s->want && s->want != r->background) {
        s->ready = done;
        s->ready_index = s->job;
        s->bound = 0;
      } else if (done) {
        destroy_texture(ctx, done); /* chosen again meanwhile, or not needed */
      }
      s->job = -1;
    }
  } else if (s->thread) {
    if (SDL_GetAtomicInt(&s->decoded)) {
      SDL_WaitThread(s->thread, NULL);
      s->thread = NULL;
      if (s->pixels) {
        if (s->job == s->want && s->want != r->background)
          s->upload = texture_upload_begin(ctx, s->pixels, s->w, s->h);
        stbi_image_free(s->pixels);
        s->pixels = NULL;
      } else {
        SDL_Log("Wyrm floor: could not decode %s", s->path);
      }
      if (!s->upload) s->job = -1;
    }
  } else if (!s->retired && s->want != r->background) {
    const background_def* bg = &BACKGROUNDS[s->want];
    const char* path = bg->path ? bg->path : BACKGROUNDS[BACKGROUND_WYRM].path;
    snprintf(s->path, sizeof(s->path), "%s", path);
    s->job = s->want;
    SDL_SetAtomicInt(&s->decoded, 0);
    s->thread = SDL_CreateThread(bg_swap_decode, "wyrm-floor", s);
    if (!s->thread) {
      /* No worker: the old way, on this thread. */
      s->job = -1;
      renderer_set_background_now(r, ctx, s->want);
    }
  }

  /* This frame's tile size follows the floor its own set shows. */
  int shown = (s->ready && (s->bound & (1u << cur))) ? s->ready_index
                                                     : r->background;
  r->global.bg_size[0] = BACKGROUNDS[shown].tile_w;
  r->global.bg_size[1] = BACKGROUNDS[shown].tile_h;
}

static void renderer_bg_swap_destroy(renderer* r, tcontext* ctx) {
  bg_swap* s = r->bg_swap;
  if (!s) return;
  if (s->thread) SDL_WaitThread(s->thread, NULL);
  if (s->pixels) stbi_image_free(s->pixels);
  if (s->upload) texture_upload_cancel(ctx, s->upload);
  if (s->ready) destroy_texture(ctx, s->ready);
  if (s->retired) destroy_texture(ctx, s->retired);
  free(s);
  r->bg_swap = NULL;
}

void renderer_set_background(renderer* r, tcontext* ctx, int index) {
  index = background_clamp(index);
  if (!r->bg_swap) {
    if (index == r->background) return;
    r->bg_swap = calloc(1, sizeof(bg_swap));
    if (!r->bg_swap) {
      renderer_set_background_now(r, ctx, index);
      return;
    }
    r->bg_swap->job = -1;
    r->bg_swap->ready_index = -1;
  }
  r->bg_swap->want = index;
}

static void renderer_set_background_now(renderer* r, tcontext* ctx, int index) {
  index = background_clamp(index);
  if (index == r->background) return;
'''

pairs("app/src/rendering/renderer.c",
      ('#include "../game/backgrounds.h"\n',
       '#include "../game/backgrounds.h"\n#include <external/stb/stb_image.h>\n'),
      ("#define BACKGROUND_LOGICAL_HEIGHT 3548.0f\n",
       "#define BACKGROUND_LOGICAL_HEIGHT 3548.0f\n\n"
       "/* The arena floor's background swap (below renderer_set_background). */\n"
       "static void renderer_bg_swap_step(renderer* r, tcontext* ctx);\n"
       "static void renderer_bg_swap_destroy(renderer* r, tcontext* ctx);\n"),
      ("void renderer_set_background(renderer* r, tcontext* ctx, int index) {\n"
       "  index = background_clamp(index);\n"
       "  if (index == r->background) return;\n",
       BG_SWAP_C),
      ("  r->global.viewport[1] = r->size[1];\n"
       "  memcpy(r->global_buffer[ctx->current_frame].data, &r->global,\n",
       "  r->global.viewport[1] = r->size[1];\n"
       "  if (r->bg_swap) renderer_bg_swap_step(r, ctx);\n"
       "  memcpy(r->global_buffer[ctx->current_frame].data, &r->global,\n"),
      ("  destroy_texture(ctx, r->tex_atlas);\n  destroy_texture(ctx, r->bg_tex);\n",
       "  renderer_bg_swap_destroy(r, ctx);\n"
       "  destroy_texture(ctx, r->tex_atlas);\n  destroy_texture(ctx, r->bg_tex);\n"))

# ------------------------------------------------------------------ 6 IPv6

pairs("app/src/constants.h",
      ("#define MAX_IPV4_LEN 19\n",
       "#define MAX_IPV4_LEN 19\n"
       "/* Any arena address, IPv6 too: \"[2001:db8::1]:444\" (OM, 2026-10-12). */\n"
       "#define MAX_ARENA_LEN 63\n"))

pairs("app/src/game/user_settings.h",
      ("} user_settings_ext;\n",
       """#ifndef WYRM_DESKTOP
  /* Bytes 42-43 were padding in every phone file written before: never read. */
  uint8_t reserved_42[2];
#endif
  /* The arena, any address (OM, 2026-10-12): IPv6 does not fit the old `ipv4`
     field. Phones: offset 44; Wyrm Desktop: 48 (after eyes_back_key). Read and
     written only through user_settings_arena / user_settings_set_arena. */
  char arena[MAX_ARENA_LEN + 1];
} user_settings_ext;
"""),
      ("void user_settings_ext_default(user_settings_ext* ext);\n",
       """void user_settings_ext_default(user_settings_ext* ext);

/* The arena to dial (OM, 2026-10-12): an IPv6 address from ext.arena, else
   `ipv4`. Setting one writes ext.arena, and `ipv4` too when it is IPv4 (older
   builds read that field). */
const char* user_settings_arena(const user_settings* settings);
void user_settings_set_arena(user_settings* settings, const char* address);
"""))

pairs("app/src/game/user_settings.c",
      ("void user_settings_ext_default(user_settings_ext* x) {\n",
       """bool server_address_is_valid(const char* address);

const char* user_settings_arena(const user_settings* settings) {
  if (settings->ext.arena[0] == '[') return settings->ext.arena;
  return settings->ipv4;
}

void user_settings_set_arena(user_settings* settings, const char* address) {
  if (!address) address = "";
  snprintf(settings->ext.arena, sizeof(settings->ext.arena), "%s", address);
  if (address[0] != '[')
    snprintf(settings->ipv4, sizeof(settings->ipv4), "%s", address);
}

#ifdef WYRM_DESKTOP
_Static_assert(offsetof(user_settings_ext, arena) == 48,
               "Wyrm Desktop's ext.arena moved");
#else
_Static_assert(offsetof(user_settings_ext, arena) == 44,
               "the phones' ext.arena moved");
#endif

void user_settings_ext_default(user_settings_ext* x) {
"""),
      ("  fixed |= ext_take_bool(&ext->snake_shadow[1], written >= shadow_at + 2);\n",
       """  fixed |= ext_take_bool(&ext->snake_shadow[1], written >= shadow_at + 2);
  {
    /* The arena (OM, 2026-10-12). A file without it, or with anything that is
       not an arena address, keeps `ipv4` alone. */
    size_t arena_at = offsetof(user_settings_ext, arena);
    if (written < arena_at + sizeof(ext->arena) ||
        memchr(ext->arena, 0, sizeof(ext->arena)) == NULL ||
        (ext->arena[0] && !server_address_is_valid(ext->arena)))
      memset(ext->arena, 0, sizeof(ext->arena));
  }
"""))

pairs("app/src/network/server.c",
      ("""bool server_address_is_valid(const char* address) {
  if (!address || !address[0] || strlen(address) > MAX_IPV4_LEN) return false;
""",
       """bool server_address_is_valid(const char* address) {
  if (!address || !address[0]) return false;
  /* IPv6 (OM, 2026-10-12, as Vlither-android): "[2001:db8::1]:444". Hex
     digits and colons (a dotted IPv4 tail allowed) inside the brackets, then
     a port. Mongoose is built with MG_ENABLE_IPV6. */
  if (address[0] == '[') {
    const char* close = strchr(address, ']');
    if (!close || close[1] != ':' || strlen(address) > MAX_ARENA_LEN) return false;
    int colons = 0;
    for (const char* p = address + 1; p < close; ++p) {
      char ch = *p;
      if (ch == ':') colons++;
      else if (!((ch >= '0' && ch <= '9') || (ch >= 'a' && ch <= 'f') ||
                 (ch >= 'A' && ch <= 'F') || ch == '.'))
        return false;
    }
    if (colons < 2 || close - address - 1 > 45) return false;
    unsigned int v6_port;
    char v6_tail = 0;
    return close[2] >= '0' && close[2] <= '9' &&
           sscanf(close + 2, "%u%c", &v6_port, &v6_tail) == 1 && v6_port > 0 &&
           v6_port <= 65535;
  }
  if (strlen(address) > MAX_IPV4_LEN) return false;
"""))

# Every reader of the arena goes through user_settings_arena(); buffers that
# hold an arena take MAX_ARENA_LEN. Replace-all items: ("ALL", old, new).
_ARENA_READERS = [
    ("ALL", "snprintf(settings->ipv4, sizeof(settings->ipv4), \"%s\", arena);",
     "user_settings_set_arena(settings, arena);"),
    ("ALL", "snprintf(settings->ipv4, sizeof(settings->ipv4), \"%s\", enter_arena);",
     "user_settings_set_arena(settings, enter_arena);"),
    ("ALL", "env->usr->usrs.ipv4", "user_settings_arena(&env->usr->usrs)"),
    ("ALL", "usr->usrs.ipv4", "user_settings_arena(&usr->usrs)"),
    ("ALL", "usrs->ipv4", "user_settings_arena(usrs)"),
    ("ALL", "settings->ipv4", "user_settings_arena(settings)"),
]
_ARENA_BUFFERS = [("ALL", "MAX_IPV4_LEN", "MAX_ARENA_LEN")]

for _relative in ["app/src/game/loop.c", "app/src/game/ui_overlay.c", "app/src/ui/lobby.c",
                  "app/src/network/callback.c", "app/src/network/ntl_net.c",
                  "app/src/platform/android_team.c"]:
    pairs(_relative, *_ARENA_READERS)
for _relative in ["app/src/platform/android_home.c", "app/src/platform/android_skin.c"]:
    pairs(_relative, *_ARENA_READERS, *_ARENA_BUFFERS)
pairs("app/src/network/arena_taint.c", *_ARENA_BUFFERS)
pairs("app/src/network/ntl_net.c", *_ARENA_BUFFERS)
pairs("app/src/network/server.c",
      ("ALL", "usrs->ipv4", "user_settings_arena(usrs)"))


def apply(root, label="engine 2026-10-12", only=None, skip_applied=False):
    root = Path(root)
    for relative, items in PAIRS.items():
        if only is not None and relative not in only:
            continue
        target = root / relative
        text = target.read_text(encoding="utf-8")
        original = text
        for item in items:
            if len(item) == 3:
                _, old, new = item
                text = text.replace(old, new)
                continue
            old, new = item
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
    # Wyrm Android's tree: python engine_sync_2026_10_12.py "<Wyrm Android>"
    print(apply(sys.argv[1], skip_applied=True), "files patched")
