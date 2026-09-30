
/* ---------------------------------------------------------------------------
 * Run screenshots for "Share this run" (OM, 2026-09-30).
 *
 * Appended to thermite/src/graphics/tcontext.c by prepare-original-engine.py,
 * so it sees the context's frames and swapchain images directly.
 *
 * The run receipt (HomeMailbox.inc WyrmIOSRecordFinishedRun, on the death
 * frame while the arena is still on screen) asks for one picture. The next
 * frame that ends copies its swapchain image inside its own command buffer,
 * after the render pass and before recording ends: PRESENT_SRC -> TRANSFER_SRC,
 * vkCmdCopyImageToBuffer into a host-visible VMA buffer, back to PRESENT_SRC.
 * Nothing waits for it. The pixels are read once that frame's own fence has
 * signalled: tcontext_begin looks without blocking every frame, and the slot's
 * normal wait guarantees it when the slot comes round again (two frames later
 * with three in flight). The copy is published as one malloc'd picture behind
 * a mutex; Swift takes it (WyrmIOSTakeRunScreenshot) and owns it from then on.
 *
 * The swapchain asks for TRANSFER_SRC only when the surface offers it and the
 * format is 8-bit BGRA/RGBA, and is created again without it if that fails.
 * On MoltenVK that usage also turns off CAMetalLayer.framebufferOnly. Without
 * it, or on any failure, there is simply no screenshot.
 *
 * Engine thread only (the iOS animation callback on main), except the mailbox.
 * ------------------------------------------------------------------------- */
#include <pthread.h>
#include <SDL3/SDL.h>

/* 0 switches the whole thing off: no TRANSFER_SRC, no copies. */
#define WYRM_RUN_CAPTURE 1
/* A request not served within this long is dropped (frames were skipped, and
   the next one drawn may no longer be the arena). */
#define WYRM_RUN_CAPTURE_WINDOW_MS 300

static pthread_mutex_t wyrm_capture_lock = PTHREAD_MUTEX_INITIALIZER;
static bool wyrm_capture_requested = false;
static uint64_t wyrm_capture_requested_at = 0;
/* The published picture, at most one; a newer request drops an untaken one. */
static uint8_t* wyrm_capture_pixels = NULL;
static int wyrm_capture_pixels_width = 0;
static int wyrm_capture_pixels_height = 0;
static int wyrm_capture_pixels_bgra = 1;

/* Render side. */
static bool wyrm_capture_usable = false;
static int wyrm_capture_bgra = 1;
static VkBuffer wyrm_capture_buffer = VK_NULL_HANDLE;
static VmaAllocation wyrm_capture_memory = NULL;
static void* wyrm_capture_mapped = NULL;
static uint32_t wyrm_capture_width = 0;
static uint32_t wyrm_capture_height = 0;
static int wyrm_capture_copy_bgra = 1;
/* Recorded into the frame being built / submitted and waiting for its fence. */
static bool wyrm_capture_recorded = false;
static bool wyrm_capture_in_flight = false;
static int wyrm_capture_frame = 0;

/* Engine thread, from the run receipt: the next frame drawn is wanted. */
void WyrmIOSRunCaptureRequest(void) {
  pthread_mutex_lock(&wyrm_capture_lock);
  wyrm_capture_requested = true;
  wyrm_capture_requested_at = (uint64_t)SDL_GetTicks();
  /* An untaken picture belongs to an older run. */
  free(wyrm_capture_pixels);
  wyrm_capture_pixels = NULL;
  pthread_mutex_unlock(&wyrm_capture_lock);
}

/* Main thread: hands over the newest picture, or returns false. Tightly
   packed 8-bit rows (stride = width * 4), sRGB-encoded, alpha meaningless;
   bgra 1 = B,G,R,A bytes, 0 = R,G,B,A. The caller frees it. */
bool WyrmIOSTakeRunScreenshot(void** pixels, int* width, int* height,
                              int* stride, int* bgra) {
  if (!pixels) return false;
  pthread_mutex_lock(&wyrm_capture_lock);
  bool ready = wyrm_capture_pixels != NULL;
  if (ready) {
    *pixels = wyrm_capture_pixels;
    if (width) *width = wyrm_capture_pixels_width;
    if (height) *height = wyrm_capture_pixels_height;
    if (stride) *stride = wyrm_capture_pixels_width * 4;
    if (bgra) *bgra = wyrm_capture_pixels_bgra;
    wyrm_capture_pixels = NULL;
  }
  pthread_mutex_unlock(&wyrm_capture_lock);
  return ready;
}

void WyrmIOSFreeRunScreenshot(void* pixels) { free(pixels); }

/* 1 BGRA, 0 RGBA, -1 a format this does not read. */
static int wyrm_capture_channel_order(VkFormat format) {
  switch (format) {
    case VK_FORMAT_B8G8R8A8_UNORM:
    case VK_FORMAT_B8G8R8A8_SRGB:
      return 1;
    case VK_FORMAT_R8G8B8A8_UNORM:
    case VK_FORMAT_R8G8B8A8_SRGB:
      return 0;
    default:
      return -1;
  }
}

/* _tcontext_create_swapchain: the extra image usage for a readback. */
static VkImageUsageFlags wyrm_capture_usage(tcontext* context,
                                            VkImageUsageFlags supported) {
  int order = wyrm_capture_channel_order(context->surface_format.format);
  bool usable = WYRM_RUN_CAPTURE && order >= 0 &&
                (supported & VK_IMAGE_USAGE_TRANSFER_SRC_BIT) != 0;
  static int logged = -1;
  if (logged != (int)usable) {
    logged = (int)usable;
    SDL_Log("Wyrm run capture: %s (format %d, surface usage 0x%x)",
            usable ? "swapchain readable" : "unavailable",
            (int)context->surface_format.format, (unsigned)supported);
  }
  wyrm_capture_usable = usable;
  wyrm_capture_bgra = order == 1;
  return usable ? VK_IMAGE_USAGE_TRANSFER_SRC_BIT : 0;
}

/* _tcontext_create_swapchain: the driver refused the readable swapchain, which
   is then built again without TRANSFER_SRC. */
static void wyrm_capture_refused(VkResult result) {
  wyrm_capture_usable = false;
  SDL_Log("Wyrm run capture: swapchain refused TRANSFER_SRC (%d); built without it",
          (int)result);
}

static void wyrm_capture_drop_buffer(tcontext* context) {
  if (wyrm_capture_buffer != VK_NULL_HANDLE)
    vmaDestroyBuffer(context->allocator, wyrm_capture_buffer, wyrm_capture_memory);
  wyrm_capture_buffer = VK_NULL_HANDLE;
  wyrm_capture_memory = NULL;
  wyrm_capture_mapped = NULL;
}

/* tcontext_end, between vkCmdEndRenderPass and vkEndCommandBuffer: this
   frame's image is final and in PRESENT_SRC_KHR (the pass's finalLayout). */
static void wyrm_capture_record(tcontext* context) {
  wyrm_capture_recorded = false;
  if (wyrm_capture_in_flight) return; /* the request waits for that one */
  pthread_mutex_lock(&wyrm_capture_lock);
  bool wanted = wyrm_capture_requested;
  uint64_t age = (uint64_t)SDL_GetTicks() - wyrm_capture_requested_at;
  wyrm_capture_requested = false;
  pthread_mutex_unlock(&wyrm_capture_lock);
  if (!wanted) return;
  if (age > WYRM_RUN_CAPTURE_WINDOW_MS) {
    SDL_Log("Wyrm run capture: skipped (no frame for %llu ms)",
            (unsigned long long)age);
    return;
  }
  if (!wyrm_capture_usable || !context->swapchain_frames ||
      context->current_image >= context->image_count ||
      context->size[0] <= 0 || context->size[1] <= 0) {
    SDL_Log("Wyrm run capture: skipped (%s)",
            wyrm_capture_usable ? "no swapchain image" : "swapchain not readable");
    return;
  }

  uint32_t width = (uint32_t)context->size[0];
  uint32_t height = (uint32_t)context->size[1];
  VmaAllocationInfo info = {0};
  VkResult made = vmaCreateBuffer(
      context->allocator,
      &(VkBufferCreateInfo){.sType = VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO,
                            .pNext = NULL,
                            .flags = 0,
                            .size = (VkDeviceSize)width * height * 4,
                            .usage = VK_BUFFER_USAGE_TRANSFER_DST_BIT,
                            .sharingMode = VK_SHARING_MODE_EXCLUSIVE},
      &(VmaAllocationCreateInfo){
          .flags = VMA_ALLOCATION_CREATE_HOST_ACCESS_RANDOM_BIT |
                   VMA_ALLOCATION_CREATE_MAPPED_BIT,
          .usage = VMA_MEMORY_USAGE_AUTO},
      &wyrm_capture_buffer, &wyrm_capture_memory, &info);
  if (made != VK_SUCCESS || !info.pMappedData) {
    if (made == VK_SUCCESS) wyrm_capture_drop_buffer(context);
    wyrm_capture_buffer = VK_NULL_HANDLE;
    wyrm_capture_memory = NULL;
    SDL_Log("Wyrm run capture: skipped (readback buffer %d)", (int)made);
    return;
  }
  wyrm_capture_mapped = info.pMappedData;
  wyrm_capture_width = width;
  wyrm_capture_height = height;
  wyrm_capture_copy_bgra = wyrm_capture_bgra;

  VkCommandBuffer cmd = context->frames[context->current_frame].cmd;
  VkImage image = context->swapchain_frames[context->current_image].image;
  const VkImageSubresourceRange colour = {
      .aspectMask = VK_IMAGE_ASPECT_COLOR_BIT,
      .baseMipLevel = 0,
      .levelCount = 1,
      .baseArrayLayer = 0,
      .layerCount = 1};

  vkCmdPipelineBarrier(
      cmd, VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT,
      VK_PIPELINE_STAGE_TRANSFER_BIT, 0, 0, NULL, 0, NULL, 1,
      &(VkImageMemoryBarrier){
          .sType = VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER,
          .pNext = NULL,
          .srcAccessMask = VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT,
          .dstAccessMask = VK_ACCESS_TRANSFER_READ_BIT,
          .oldLayout = VK_IMAGE_LAYOUT_PRESENT_SRC_KHR,
          .newLayout = VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL,
          .srcQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED,
          .dstQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED,
          .image = image,
          .subresourceRange = colour});

  vkCmdCopyImageToBuffer(
      cmd, image, VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL, wyrm_capture_buffer, 1,
      &(VkBufferImageCopy){
          .bufferOffset = 0,
          .bufferRowLength = 0,
          .bufferImageHeight = 0,
          .imageSubresource = {.aspectMask = VK_IMAGE_ASPECT_COLOR_BIT,
                               .mipLevel = 0,
                               .baseArrayLayer = 0,
                               .layerCount = 1},
          .imageOffset = {0, 0, 0},
          .imageExtent = {width, height, 1}});

  /* The image goes back for presentation; the buffer becomes host-readable. */
  vkCmdPipelineBarrier(
      cmd, VK_PIPELINE_STAGE_TRANSFER_BIT,
      VK_PIPELINE_STAGE_BOTTOM_OF_PIPE_BIT | VK_PIPELINE_STAGE_HOST_BIT, 0, 0,
      NULL, 1,
      &(VkBufferMemoryBarrier){
          .sType = VK_STRUCTURE_TYPE_BUFFER_MEMORY_BARRIER,
          .pNext = NULL,
          .srcAccessMask = VK_ACCESS_TRANSFER_WRITE_BIT,
          .dstAccessMask = VK_ACCESS_HOST_READ_BIT,
          .srcQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED,
          .dstQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED,
          .buffer = wyrm_capture_buffer,
          .offset = 0,
          .size = VK_WHOLE_SIZE},
      1,
      &(VkImageMemoryBarrier){
          .sType = VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER,
          .pNext = NULL,
          .srcAccessMask = VK_ACCESS_TRANSFER_READ_BIT,
          .dstAccessMask = 0,
          .oldLayout = VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL,
          .newLayout = VK_IMAGE_LAYOUT_PRESENT_SRC_KHR,
          .srcQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED,
          .dstQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED,
          .image = image,
          .subresourceRange = colour});
  wyrm_capture_recorded = true;
}

/* tcontext_end, right after vkQueueSubmit. */
static void wyrm_capture_submitted(tcontext* context, bool submitted) {
  if (!wyrm_capture_recorded) return;
  wyrm_capture_recorded = false;
  if (!submitted) {
    wyrm_capture_drop_buffer(context);
    SDL_Log("Wyrm run capture: skipped (frame not submitted)");
    return;
  }
  wyrm_capture_in_flight = true;
  wyrm_capture_frame = context->current_frame;
}

/* tcontext_begin, after this slot's fence wait and before its reset. A fence
   is reset only here, for the current slot, so the captured slot's fence still
   belongs to the captured frame. Never blocks: not ready = look next frame. */
static void wyrm_capture_harvest(tcontext* context) {
  if (!wyrm_capture_in_flight) return;
  if (wyrm_capture_frame < 0 || wyrm_capture_frame >= context->fif ||
      vkGetFenceStatus(context->device,
                       context->frames[wyrm_capture_frame].wait_fence) !=
          VK_SUCCESS)
    return;
  wyrm_capture_in_flight = false;
  size_t bytes = (size_t)wyrm_capture_width * wyrm_capture_height * 4;
  uint8_t* pixels = wyrm_capture_mapped ? malloc(bytes) : NULL;
  if (pixels &&
      vmaInvalidateAllocation(context->allocator, wyrm_capture_memory, 0,
                              VK_WHOLE_SIZE) == VK_SUCCESS) {
    memcpy(pixels, wyrm_capture_mapped, bytes);
  } else {
    free(pixels);
    pixels = NULL;
  }
  wyrm_capture_drop_buffer(context);
  if (!pixels) {
    SDL_Log("Wyrm run capture: skipped (could not read %ux%u)",
            wyrm_capture_width, wyrm_capture_height);
    return;
  }
  pthread_mutex_lock(&wyrm_capture_lock);
  free(wyrm_capture_pixels);
  wyrm_capture_pixels = pixels;
  wyrm_capture_pixels_width = (int)wyrm_capture_width;
  wyrm_capture_pixels_height = (int)wyrm_capture_height;
  wyrm_capture_pixels_bgra = wyrm_capture_copy_bgra;
  pthread_mutex_unlock(&wyrm_capture_lock);
  SDL_Log("Wyrm run capture: %ux%u %s ready", wyrm_capture_width,
          wyrm_capture_height, wyrm_capture_copy_bgra ? "BGRA" : "RGBA");
}

/* tcontext_destroy, before the allocator goes. */
static void wyrm_capture_release(tcontext* context) {
  if (wyrm_capture_buffer == VK_NULL_HANDLE) return;
  vkDeviceWaitIdle(context->device);
  wyrm_capture_drop_buffer(context);
  wyrm_capture_recorded = false;
  wyrm_capture_in_flight = false;
}
