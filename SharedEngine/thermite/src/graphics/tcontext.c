#include "tcontext.h"

#include <stdio.h>
#include <string.h>

#ifdef VLITHER_ANDROID
#include <SDL3/SDL_vulkan.h>
#include "platform/android_startup.h"
#define TCONTEXT_LOG(...) SDL_Log(__VA_ARGS__)
#else
#define TCONTEXT_LOG(...) ((void)0)
#endif

void _tcontext_create_instance(tcontext* context) {
#ifdef VLITHER_ANDROID
  Uint32 instance_ext_count = 0;
  const char* const* instance_ext_names =
      SDL_Vulkan_GetInstanceExtensions(&instance_ext_count);
#else
  uint32_t instance_ext_count;
  const char** instance_ext_names =
      glfwGetRequiredInstanceExtensions(&instance_ext_count);
#endif

  VkResult result = vkCreateInstance(
      &(VkInstanceCreateInfo){
          .sType = VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO,
          .pNext = NULL,
          .flags = 0,
          .pApplicationInfo =
              &(VkApplicationInfo){.sType = VK_STRUCTURE_TYPE_APPLICATION_INFO,
                                   .pNext = NULL,
                                   .pApplicationName = "app",
                                   .applicationVersion = 1,
                                   .pEngineName = "thermite",
                                   .engineVersion = 1,
                                   .apiVersion = VK_API_VERSION_1_0},
#ifdef TDEBUG
          .enabledLayerCount = 1,
#else
          .enabledLayerCount = 0,
#endif
          .ppEnabledLayerNames = (const char*[]){"VK_LAYER_KHRONOS_validation"},
          .enabledExtensionCount = instance_ext_count,
          .ppEnabledExtensionNames = instance_ext_names},
      NULL, &context->instance);
  TCONTEXT_LOG("Vlither: vkCreateInstance=%d", (int)result);
#ifdef VLITHER_ANDROID
  if (result == VK_SUCCESS) {
    android_startup_stage(4, "Vulkan instance created",
                          "Android Vulkan extensions were accepted");
  } else {
    char detail[96];
    snprintf(detail, sizeof(detail), "vkCreateInstance returned %d", (int)result);
    android_startup_failure(4, "Vulkan instance failed", detail);
  }
#endif
}

bool _tcontext_create_surface(tcontext* context, twindow* window) {
  context->surface = VK_NULL_HANDLE;
#ifdef VLITHER_ANDROID
  if (!SDL_Vulkan_CreateSurface(window->handle, context->instance, NULL,
                                &context->surface)) {
    SDL_Log("Vlither: Vulkan surface creation failed: %s", SDL_GetError());
    android_startup_failure(4, "Vulkan surface failed", SDL_GetError());
    return false;
  }
  TCONTEXT_LOG("Vlither: Vulkan surface ready");
#else
  if (glfwCreateWindowSurface(context->instance, window->handle, NULL,
                              &context->surface) != VK_SUCCESS)
    return false;
#endif
  return context->surface != VK_NULL_HANDLE;
}

int _tcontext_select_device(tcontext* context) {
  uint32_t device_count = 0;
  VkResult result =
      vkEnumeratePhysicalDevices(context->instance, &device_count, NULL);
  TCONTEXT_LOG("Vlither: physical device query=%d count=%u", (int)result,
               device_count);
  if (result != VK_SUCCESS || device_count == 0)
  {
#ifdef VLITHER_ANDROID
    char detail[96];
    snprintf(detail, sizeof(detail),
             "vkEnumeratePhysicalDevices returned %d with %u devices",
             (int)result, device_count);
    android_startup_failure(5, "No compatible Vulkan GPU", detail);
#endif
    return 0;
  }

  VkPhysicalDevice* devices = calloc(device_count, sizeof(VkPhysicalDevice));
  typedef struct {
    int score;
    VkSurfaceFormatKHR selected_format;
    int selected_queue;
    bool supports_immediate;
    bool supports_fifo;
    bool supports_swapchain;
  } score;
  score* scores = calloc(device_count, sizeof(score));
  result = vkEnumeratePhysicalDevices(context->instance, &device_count, devices);
  TCONTEXT_LOG("Vlither: physical device enumeration=%d", (int)result);
  if (result != VK_SUCCESS) {
    free(scores);
    free(devices);
    return 0;
  }

  for (uint32_t i = 0; i < device_count; i++) {
    scores[i].score = -1;
    int selected_format = -1;
    scores[i].selected_queue = -1;
    scores[i].supports_immediate = false;
    scores[i].supports_fifo = false;
    scores[i].supports_swapchain = false;

    VkPhysicalDeviceProperties properties = {0};
    vkGetPhysicalDeviceProperties(devices[i], &properties);
    TCONTEXT_LOG("Vlither: probing GPU[%u]=%s", i, properties.deviceName);

    uint32_t format_count = 0;
    result = vkGetPhysicalDeviceSurfaceFormatsKHR(
        devices[i], context->surface, &format_count, NULL);
    TCONTEXT_LOG("Vlither: surface format query=%d count=%u", (int)result,
                 format_count);
    if (result != VK_SUCCESS || format_count == 0)
      continue;
    VkSurfaceFormatKHR* formats = calloc(format_count, sizeof(*formats));
    result = vkGetPhysicalDeviceSurfaceFormatsKHR(
        devices[i], context->surface, &format_count, formats);
    if (result != VK_SUCCESS) {
      free(formats);
      continue;
    }

    for (uint32_t j = 0; j < format_count; j++) {
      if ((formats[j].colorSpace == VK_COLOR_SPACE_SRGB_NONLINEAR_KHR &&
           formats[j].format == VK_FORMAT_R8G8B8A8_UNORM) ||
          (formats[j].colorSpace == VK_COLOR_SPACE_SRGB_NONLINEAR_KHR &&
           formats[j].format == VK_FORMAT_B8G8R8A8_UNORM)) {
        selected_format = j;
        break;
      }
    }
    if (selected_format == -1)
      selected_format = 0;

    uint32_t present_mode_count = 0;
    result = vkGetPhysicalDeviceSurfacePresentModesKHR(
        devices[i], context->surface, &present_mode_count, NULL);
    TCONTEXT_LOG("Vlither: present mode query=%d count=%u", (int)result,
                 present_mode_count);
    if (result != VK_SUCCESS || present_mode_count == 0) {
      free(formats);
      continue;
    }
    VkPresentModeKHR* present_modes =
        calloc(present_mode_count, sizeof(*present_modes));
    result = vkGetPhysicalDeviceSurfacePresentModesKHR(
        devices[i], context->surface, &present_mode_count, present_modes);
    if (result != VK_SUCCESS) {
      free(present_modes);
      free(formats);
      continue;
    }

    for (uint32_t j = 0; j < present_mode_count; j++) {
      if (present_modes[j] == VK_PRESENT_MODE_IMMEDIATE_KHR)
        scores[i].supports_immediate = true;
      if (present_modes[j] == VK_PRESENT_MODE_FIFO_KHR)
        scores[i].supports_fifo = true;
    }

    uint32_t queue_family_count = 0;
    vkGetPhysicalDeviceQueueFamilyProperties(devices[i], &queue_family_count,
                                             NULL);
    TCONTEXT_LOG("Vlither: queue family count=%u", queue_family_count);
    VkQueueFamilyProperties* queue_family_proprties =
        calloc(queue_family_count, sizeof(VkQueueFamilyProperties));
    vkGetPhysicalDeviceQueueFamilyProperties(devices[i], &queue_family_count,
                                             queue_family_proprties);

    for (uint32_t j = 0; j < queue_family_count; j++) {
      VkBool32 supports_presentation = VK_FALSE;
      result = vkGetPhysicalDeviceSurfaceSupportKHR(
          devices[i], j, context->surface, &supports_presentation);

      if ((queue_family_proprties[j].queueFlags & VK_QUEUE_GRAPHICS_BIT) &&
          supports_presentation && result == VK_SUCCESS) {
        scores[i].selected_queue = (int)j;
        break;
      }
    }

    free(queue_family_proprties);

    uint32_t extension_count = 0;
    result = vkEnumerateDeviceExtensionProperties(devices[i], NULL,
                                                  &extension_count, NULL);
    TCONTEXT_LOG("Vlither: extension query=%d count=%u", (int)result,
                 extension_count);
    VkExtensionProperties* extensions =
        calloc(extension_count, sizeof(VkExtensionProperties));
    if (result == VK_SUCCESS)
      result = vkEnumerateDeviceExtensionProperties(
          devices[i], NULL, &extension_count, extensions);

    for (uint32_t j = 0; result == VK_SUCCESS && j < extension_count; j++) {
      if (strcmp(extensions[j].extensionName,
                 VK_KHR_SWAPCHAIN_EXTENSION_NAME) == 0) {
        scores[i].supports_swapchain = true;
        break;
      }
    }

    free(extensions);

    if (selected_format != -1 && scores[i].supports_fifo &&
        scores[i].supports_swapchain && scores[i].selected_queue != -1 &&
        properties.deviceType != VK_PHYSICAL_DEVICE_TYPE_CPU) {
      scores[i].selected_format = formats[selected_format];
      scores[i].score = 0;

      if (properties.deviceType == VK_PHYSICAL_DEVICE_TYPE_DISCRETE_GPU)
        scores[i].score++;
    }

    free(present_modes);
    free(formats);
  }

  int selected_device = -1;
  int highest_score = -1;

  for (uint32_t i = 0; i < device_count; i++) {
    if (scores[i].score == -1) continue;

    if (scores[i].score > highest_score) {
      highest_score = scores[i].score;
      selected_device = i;
    }
  }

  if (selected_device == -1) {
    printf("No GPU found.\n");
    free(scores);
    free(devices);
#ifdef VLITHER_ANDROID
    android_startup_failure(
        5, "No compatible Vulkan configuration",
        "No GPU exposed a graphics/present queue, surface format and swapchain");
#endif
    return 0;
  }

  context->queue_family = scores[selected_device].selected_queue;
  context->surface_format = scores[selected_device].selected_format;
  context->supports_immediate = scores[selected_device].supports_immediate;

  VkPhysicalDeviceProperties properties;
  context->ph_device = devices[selected_device];
  vkGetPhysicalDeviceProperties(context->ph_device, &properties);
  TCONTEXT_LOG("Vlither: selected GPU=%s API=%u.%u.%u", properties.deviceName,
               VK_API_VERSION_MAJOR(properties.apiVersion),
               VK_API_VERSION_MINOR(properties.apiVersion),
               VK_API_VERSION_PATCH(properties.apiVersion));
#ifdef VLITHER_ANDROID
  char api_version[32];
  char gpu_detail[160];
  snprintf(api_version, sizeof(api_version), "%u.%u.%u",
           VK_API_VERSION_MAJOR(properties.apiVersion),
           VK_API_VERSION_MINOR(properties.apiVersion),
           VK_API_VERSION_PATCH(properties.apiVersion));
  snprintf(gpu_detail, sizeof(gpu_detail), "%s · Vulkan %s · max texture %u px",
           properties.deviceName, api_version,
           properties.limits.maxImageDimension2D);
  android_startup_stage(5, "Compatible GPU selected", gpu_detail);
  android_startup_gpu(properties.deviceName, api_version,
                      (int)properties.limits.maxImageDimension2D);
#endif
  printf("GPU: %s\nMax API version: %d.%d.%d\nCurrent API version: %d.%d.%d\n",
         properties.deviceName, VK_API_VERSION_MAJOR(properties.apiVersion),
         VK_API_VERSION_MINOR(properties.apiVersion),
         VK_API_VERSION_PATCH(properties.apiVersion),
         VK_API_VERSION_MAJOR(VK_API_VERSION_1_0),
         VK_API_VERSION_MINOR(VK_API_VERSION_1_0),
         VK_API_VERSION_PATCH(VK_API_VERSION_1_0));

  free(scores);
  free(devices);
  return 1;
}

void _tcontext_create_device(tcontext* context) {
  VkResult result = vkCreateDevice(
      context->ph_device,
      &(VkDeviceCreateInfo){
          .sType = VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO,
          .pNext = NULL,
          .flags = 0,
          .queueCreateInfoCount = 1,
          .pQueueCreateInfos =
              &(VkDeviceQueueCreateInfo){
                  .sType = VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO,
                  .pNext = NULL,
                  .flags = 0,
                  .queueFamilyIndex = context->queue_family,
                  .queueCount = 1,
                  .pQueuePriorities = &(float){1.0f}},
          .enabledLayerCount = 0,
          .ppEnabledLayerNames = NULL,
          .enabledExtensionCount = 1,
          .ppEnabledExtensionNames =
              (const char*[]){VK_KHR_SWAPCHAIN_EXTENSION_NAME}},
      NULL, &context->device);
  TCONTEXT_LOG("Vlither: vkCreateDevice=%d", (int)result);
#ifdef VLITHER_ANDROID
  if (result == VK_SUCCESS) {
    android_startup_stage(6, "Logical render device ready",
                          "Graphics queue and VK_KHR_swapchain are available");
  } else {
    char detail[96];
    snprintf(detail, sizeof(detail), "vkCreateDevice returned %d", (int)result);
    android_startup_failure(6, "Logical render device failed", detail);
  }
#endif

  vkGetDeviceQueue(context->device, context->queue_family, 0, &context->queue);
}

void _tcontext_create_swapchain(tcontext* context, bool vsync) {
  VkSurfaceCapabilitiesKHR capabilities;
  vkGetPhysicalDeviceSurfaceCapabilitiesKHR(context->ph_device,
                                            context->surface, &capabilities);

  context->size[0] = capabilities.currentExtent.width;
  context->size[1] = capabilities.currentExtent.height;
  context->min_image_count = capabilities.minImageCount + 1;
  if (capabilities.maxImageCount > 0 &&
      context->min_image_count > capabilities.maxImageCount)
    context->min_image_count = capabilities.maxImageCount;

  VkPresentModeKHR selected_present_mode = VK_PRESENT_MODE_FIFO_KHR;
#ifndef VLITHER_ANDROID
  if (!vsync) {
    uint32_t count = 0;
    if (vkGetPhysicalDeviceSurfacePresentModesKHR(
            context->ph_device, context->surface, &count, NULL) == VK_SUCCESS &&
        count > 0) {
      VkPresentModeKHR* modes = calloc(count, sizeof(*modes));
      if (vkGetPhysicalDeviceSurfacePresentModesKHR(
              context->ph_device, context->surface, &count, modes) ==
          VK_SUCCESS) {
        for (uint32_t i = 0; i < count; ++i) {
          if (modes[i] == VK_PRESENT_MODE_MAILBOX_KHR) {
            selected_present_mode = VK_PRESENT_MODE_MAILBOX_KHR;
            break;
          }
          if (modes[i] == VK_PRESENT_MODE_IMMEDIATE_KHR)
            selected_present_mode = VK_PRESENT_MODE_IMMEDIATE_KHR;
        }
      }
      free(modes);
    }
  }
#else
  /*
   * IMMEDIATE on Android too, where the device actually offers it.
   *
   * This used to be hard-wired to FIFO on the reasoning that FIFO is the one
   * mode every Android Vulkan implementation must support. That is true and it
   * was the wrong conclusion: it is a reason to keep FIFO as the fallback, not
   * a reason to refuse IMMEDIATE on a device that advertises it. Vlither runs
   * the same engine on the same phones and picks IMMEDIATE whenever
   * `supports_immediate` is set, which is where its uncapped frame rate comes
   * from — the renderer was never the thing holding Wyrm to the display's
   * refresh, this line was.
   *
   * `supports_immediate` is read from the surface's own present-mode list while
   * the device is chosen, so a driver that does not offer it still gets FIFO
   * and nothing has to be special-cased per phone.
   */
  if (!vsync && context->supports_immediate)
    selected_present_mode = VK_PRESENT_MODE_IMMEDIATE_KHR;
#endif

  VkCompositeAlphaFlagBitsKHR composite_alpha =
      VK_COMPOSITE_ALPHA_OPAQUE_BIT_KHR;
  if (!(capabilities.supportedCompositeAlpha & composite_alpha)) {
    const VkCompositeAlphaFlagBitsKHR candidates[] = {
        VK_COMPOSITE_ALPHA_PRE_MULTIPLIED_BIT_KHR,
        VK_COMPOSITE_ALPHA_POST_MULTIPLIED_BIT_KHR,
        VK_COMPOSITE_ALPHA_INHERIT_BIT_KHR};
    for (uint32_t i = 0; i < sizeof(candidates) / sizeof(candidates[0]); ++i) {
      if (capabilities.supportedCompositeAlpha & candidates[i]) {
        composite_alpha = candidates[i];
        break;
      }
    }
  }

  // Android may report a 90-degree current transform while SDL has already
  // delivered landscape pixel dimensions. Prefer an identity swapchain when
  // the surface supports it so the compositor does not rotate our landscape
  // render target a second time.
  VkSurfaceTransformFlagBitsKHR pre_transform = capabilities.currentTransform;
#ifdef VLITHER_ANDROID
  if (capabilities.supportedTransforms & VK_SURFACE_TRANSFORM_IDENTITY_BIT_KHR)
    pre_transform = VK_SURFACE_TRANSFORM_IDENTITY_BIT_KHR;
  TCONTEXT_LOG("Vlither: surface transform current=%u selected=%u supported=%u",
               (uint32_t)capabilities.currentTransform,
               (uint32_t)pre_transform,
               (uint32_t)capabilities.supportedTransforms);
#endif

  VkResult result = vkCreateSwapchainKHR(
      context->device,
      &(VkSwapchainCreateInfoKHR){
          .sType = VK_STRUCTURE_TYPE_SWAPCHAIN_CREATE_INFO_KHR,
          .pNext = NULL,
          .flags = 0,
          .surface = context->surface,
          .minImageCount = context->min_image_count,
          .imageFormat = context->surface_format.format,
          .imageColorSpace = context->surface_format.colorSpace,
          .imageExtent = capabilities.currentExtent,
          .imageArrayLayers = 1,
          .imageUsage = VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT,
          .imageSharingMode = VK_SHARING_MODE_EXCLUSIVE,
          .queueFamilyIndexCount = 0,
          .pQueueFamilyIndices = NULL,
          .preTransform = pre_transform,
          .compositeAlpha = composite_alpha,
          .presentMode = selected_present_mode,
          .clipped = VK_TRUE,
          .oldSwapchain = context->old_swapchain},
      NULL, &context->swapchain);
  TCONTEXT_LOG("Vlither: vkCreateSwapchainKHR=%d size=%ux%u images=%u mode=%d",
               (int)result, capabilities.currentExtent.width,
               capabilities.currentExtent.height, context->min_image_count,
               (int)selected_present_mode);
#ifdef VLITHER_ANDROID
  if (result == VK_SUCCESS) {
    char detail[128];
    snprintf(detail, sizeof(detail), "%u x %u · %u images · FIFO presentation",
             capabilities.currentExtent.width, capabilities.currentExtent.height,
             context->min_image_count);
    android_startup_stage(7, "Swapchain ready", detail);
  } else {
    char detail[96];
    snprintf(detail, sizeof(detail), "vkCreateSwapchainKHR returned %d", (int)result);
    android_startup_failure(7, "Swapchain creation failed", detail);
  }
#endif
}

void _tcontext_create_renderpass(tcontext* context) {
  VkResult result = vkCreateRenderPass(
      context->device,
      &(VkRenderPassCreateInfo){
          .sType = VK_STRUCTURE_TYPE_RENDER_PASS_CREATE_INFO,
          .pNext = NULL,
          .flags = 0,
          .attachmentCount = 1,
          .pAttachments =
              &(VkAttachmentDescription){
                  .flags = 0,
                  .format = context->surface_format.format,
                  .samples = VK_SAMPLE_COUNT_1_BIT,
                  .loadOp = VK_ATTACHMENT_LOAD_OP_CLEAR,
                  .storeOp = VK_ATTACHMENT_STORE_OP_STORE,
                  .stencilLoadOp = VK_ATTACHMENT_LOAD_OP_DONT_CARE,
                  .stencilStoreOp = VK_ATTACHMENT_STORE_OP_DONT_CARE,
                  .initialLayout = VK_IMAGE_LAYOUT_UNDEFINED,
                  .finalLayout = VK_IMAGE_LAYOUT_PRESENT_SRC_KHR},
          .subpassCount = 1,
          .pSubpasses =
              &(VkSubpassDescription){
                  .flags = 0,
                  .pipelineBindPoint = VK_PIPELINE_BIND_POINT_GRAPHICS,
                  .inputAttachmentCount = 0,
                  .pInputAttachments = NULL,
                  .colorAttachmentCount = 1,
                  .pColorAttachments =
                      &(VkAttachmentReference){
                          .attachment = 0,
                          .layout = VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL},
                  .pResolveAttachments = NULL,
                  .pDepthStencilAttachment = NULL,
                  .preserveAttachmentCount = 0,
                  .pPreserveAttachments = NULL},
          .dependencyCount = 2,
          .pDependencies =
              (VkSubpassDependency[]){
                  {.srcSubpass = VK_SUBPASS_EXTERNAL,
                   .dstSubpass = 0,
                   .srcStageMask = VK_PIPELINE_STAGE_EARLY_FRAGMENT_TESTS_BIT |
                                   VK_PIPELINE_STAGE_LATE_FRAGMENT_TESTS_BIT,
                   .dstStageMask = VK_PIPELINE_STAGE_EARLY_FRAGMENT_TESTS_BIT |
                                   VK_PIPELINE_STAGE_LATE_FRAGMENT_TESTS_BIT,
                   .srcAccessMask =
                       VK_ACCESS_DEPTH_STENCIL_ATTACHMENT_WRITE_BIT,
                   .dstAccessMask =
                       VK_ACCESS_DEPTH_STENCIL_ATTACHMENT_WRITE_BIT |
                       VK_ACCESS_DEPTH_STENCIL_ATTACHMENT_READ_BIT,
                   .dependencyFlags = 0},
                  {.srcSubpass = VK_SUBPASS_EXTERNAL,
                   .dstSubpass = 0,
                   .srcStageMask =
                       VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT,
                   .dstStageMask =
                       VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT,
                   .srcAccessMask = 0,
                   .dstAccessMask = VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT |
                                    VK_ACCESS_COLOR_ATTACHMENT_READ_BIT,
                   .dependencyFlags = 0}}},
      NULL, &context->renderpass);
  TCONTEXT_LOG("Vlither: vkCreateRenderPass=%d", (int)result);
}

void _tcontext_create_views(tcontext* context) {
  vkGetSwapchainImagesKHR(context->device, context->swapchain,
                          &context->image_count, NULL);
  context->swapchain_frames =
      malloc(context->image_count * sizeof(_tcontext_swapchain_frame));

  VkImage* images = malloc(context->image_count * sizeof(VkImage));
  vkGetSwapchainImagesKHR(context->device, context->swapchain,
                          &context->image_count, images);

  for (uint32_t i = 0; i < context->image_count; i++)
    context->swapchain_frames[i].image = images[i];

  free(images);

  for (uint32_t i = 0; i < context->image_count; i++) {
    vkCreateImageView(
        context->device,
        &(VkImageViewCreateInfo){
            .sType = VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO,
            .pNext = NULL,
            .flags = 0,
            .image = context->swapchain_frames[i].image,
            .viewType = VK_IMAGE_VIEW_TYPE_2D,
            .format = context->surface_format.format,
            .components =
                (VkComponentMapping){.r = VK_COMPONENT_SWIZZLE_IDENTITY,
                                     .g = VK_COMPONENT_SWIZZLE_IDENTITY,
                                     .b = VK_COMPONENT_SWIZZLE_IDENTITY,
                                     .a = VK_COMPONENT_SWIZZLE_IDENTITY},
            .subresourceRange =
                (VkImageSubresourceRange){
                    .aspectMask = VK_IMAGE_ASPECT_COLOR_BIT,
                    .baseMipLevel = 0,
                    .levelCount = 1,
                    .baseArrayLayer = 0,
                    .layerCount = 1}},
        NULL, &context->swapchain_frames[i].image_view);

    vkCreateFramebuffer(
        context->device,
        &(VkFramebufferCreateInfo){
            .sType = VK_STRUCTURE_TYPE_FRAMEBUFFER_CREATE_INFO,
            .pNext = NULL,
            .flags = 0,
            .renderPass = context->renderpass,
            .attachmentCount = 1,
            .pAttachments = &context->swapchain_frames[i].image_view,
            .width = context->size[0],
            .height = context->size[1],
            .layers = 1},
        NULL, &context->swapchain_frames[i].framebuffer);
  }
}

static void _tcontext_create_render_completes(tcontext* context) {
  context->render_completes =
      calloc(context->image_count, sizeof(*context->render_completes));

  for (uint32_t i = 0; i < context->image_count; i++) {
    VkResult result = vkCreateSemaphore(
        context->device,
        &(VkSemaphoreCreateInfo){
            .sType = VK_STRUCTURE_TYPE_SEMAPHORE_CREATE_INFO,
            .pNext = NULL,
            .flags = 0},
        NULL, &context->render_completes[i]);
    if (result != VK_SUCCESS) {
      TCONTEXT_LOG("Vlither: render semaphore creation failed at %u: %d", i,
                   (int)result);
    }
  }
}

static void _tcontext_destroy_render_completes(tcontext* context,
                                                uint32_t image_count) {
  if (!context->render_completes) return;

  for (uint32_t i = 0; i < image_count; i++) {
    if (context->render_completes[i] != VK_NULL_HANDLE) {
      vkDestroySemaphore(context->device, context->render_completes[i], NULL);
    }
  }
  free(context->render_completes);
  context->render_completes = NULL;
}

void _tcontext_create_frames(tcontext* context) {
  context->frames = calloc(context->fif, sizeof(tcontext_frame));

  for (int i = 0; i < context->fif; i++) {
    vkCreateSemaphore(context->device,
                      &(VkSemaphoreCreateInfo){
                          .sType = VK_STRUCTURE_TYPE_SEMAPHORE_CREATE_INFO,
                          .pNext = NULL,
                          .flags = 0},
                      NULL, &context->frames[i].present_complete);
    vkCreateFence(
        context->device,
        &(VkFenceCreateInfo){.sType = VK_STRUCTURE_TYPE_FENCE_CREATE_INFO,
                             .pNext = NULL,
                             .flags = VK_FENCE_CREATE_SIGNALED_BIT},
        NULL, &context->frames[i].wait_fence);
  }

  _tcontext_create_render_completes(context);

  vkCreateCommandPool(
      context->device,
      &(VkCommandPoolCreateInfo){
          .sType = VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO,
          .pNext = NULL,
          .flags = VK_COMMAND_POOL_CREATE_RESET_COMMAND_BUFFER_BIT,
          .queueFamilyIndex = context->queue_family},
      NULL, &context->cmd_pool);

  VkCommandBuffer* cmd_buffers =
      malloc((context->fif + 1) * sizeof(VkCommandBuffer));
  vkAllocateCommandBuffers(
      context->device,
      &(VkCommandBufferAllocateInfo){
          .sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO,
          .pNext = NULL,
          .commandPool = context->cmd_pool,
          .level = VK_COMMAND_BUFFER_LEVEL_PRIMARY,
          .commandBufferCount = context->fif + 1},
      cmd_buffers);

  for (int i = 0; i < context->fif; i++)
    context->frames[i].cmd = cmd_buffers[i];

  context->transfer_cmd = cmd_buffers[context->fif];

  free(cmd_buffers);

  vkCreateFence(
      context->device,
      &(VkFenceCreateInfo){.sType = VK_STRUCTURE_TYPE_FENCE_CREATE_INFO,
                           .pNext = NULL,
                           .flags = 0},
      NULL, &context->transfer_fence);
}

void _tcontext_create_allocator(tcontext* context) {
  vmaCreateAllocator(
      &(VmaAllocatorCreateInfo){.flags = 0,
                                .physicalDevice = context->ph_device,
                                .device = context->device,
                                .instance = context->instance,
                                .vulkanApiVersion = VK_API_VERSION_1_0},
      &context->allocator);
}

VkShaderModule tcontext_create_shader(tcontext* context, const char* filename) {
  FILE* file = fopen(filename, "rb");
  if (!file) {
    printf("error reading file: \'%s\'\n", filename);
    return VK_NULL_HANDLE;
  }

  fseek(file, 0, SEEK_END);
  long file_size = ftell(file);
  rewind(file);

  unsigned int* content = malloc(file_size);
  fread(content, sizeof(unsigned int), file_size / sizeof(unsigned int), file);
  fclose(file);

  VkShaderModule module;
  VkResult shader_result = vkCreateShaderModule(context->device,
                       &(VkShaderModuleCreateInfo){
                           .sType = VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO,
                           .pNext = NULL,
                           .flags = 0,
                           .codeSize = file_size,
                           .pCode = content,
                       },
                       NULL, &module);
#ifdef VLITHER_ANDROID
  if (shader_result != VK_SUCCESS) {
    char detail[256];
    snprintf(detail, sizeof(detail), "%s · vkCreateShaderModule returned %d",
             filename, (int)shader_result);
    android_startup_failure(9, "Shader module failed", detail);
  }
#endif
  free(content);
  return module;
}

void _tcontext_create_descriptor_pool(tcontext* context) {
  vkCreateDescriptorPool(
      context->device,
      &(VkDescriptorPoolCreateInfo){
          .sType = VK_STRUCTURE_TYPE_DESCRIPTOR_POOL_CREATE_INFO,
          .pNext = NULL,
          .flags = VK_DESCRIPTOR_POOL_CREATE_FREE_DESCRIPTOR_SET_BIT,
          .maxSets = 20,
          .poolSizeCount = 2,
          .pPoolSizes =
              (VkDescriptorPoolSize[]){
                  {VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER, 20},
                  {VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER, 20},
              }},
      NULL, &context->descriptor_pool);
}

tcontext* tcontext_create(twindow* window, bool vsync, int fif) {
  tcontext* context = calloc(1, sizeof(tcontext));
  context->fif = fif;
  context->old_swapchain = VK_NULL_HANDLE;
  context->swapchain_ok = true;
  context->surface_lost = false;
  context->last_present_succeeded = false;
  context->current_frame = 0;

  _tcontext_create_instance(context);
  if (context->instance == VK_NULL_HANDLE) {
    free(context);
    return NULL;
  }
  if (!_tcontext_create_surface(context, window)) {
    vkDestroyInstance(context->instance, NULL);
    free(context);
    return NULL;
  }
  if (!_tcontext_select_device(context)) {
    return NULL;
  }
  _tcontext_create_device(context);
  if (context->device == VK_NULL_HANDLE) return NULL;
  _tcontext_create_swapchain(context, vsync);
  if (context->swapchain == VK_NULL_HANDLE) return NULL;
  _tcontext_create_renderpass(context);
  _tcontext_create_views(context);
  TCONTEXT_LOG("Vlither: swapchain views ready (%u)", context->image_count);
  _tcontext_create_frames(context);
  TCONTEXT_LOG("Vlither: frame resources ready");
  _tcontext_create_allocator(context);
  TCONTEXT_LOG("Vlither: VMA allocator ready");
  _tcontext_create_descriptor_pool(context);
  TCONTEXT_LOG("Vlither: descriptor pool ready");
  return context;
}

void tcontext_resize(tcontext* context, const ivec2 size, bool vsync) {
  if (context->surface_lost || context->surface == VK_NULL_HANDLE) return;
  tcontext_wait_idle(context);
  context->old_swapchain = context->swapchain;
  context->swapchain = VK_NULL_HANDLE;
  const uint32_t old_image_count = context->image_count;

  // A recreated Android swapchain is allowed to expose a different number of
  // images (for example 5 before rotation and 6 afterwards). Per-image render
  // semaphores must therefore be rebuilt alongside the swapchain views.
  _tcontext_destroy_render_completes(context, old_image_count);

  for (uint32_t i = 0; i < old_image_count; i++) {
    vkDestroyFramebuffer(context->device,
                         context->swapchain_frames[i].framebuffer, NULL);
    vkDestroyImageView(context->device, context->swapchain_frames[i].image_view,
                       NULL);
  }
  free(context->swapchain_frames);

  _tcontext_create_swapchain(context, vsync);
  if (context->swapchain == VK_NULL_HANDLE) {
    context->swapchain_ok = false;
    context->old_swapchain = VK_NULL_HANDLE;
    return;
  }
  vkDestroySwapchainKHR(context->device, context->old_swapchain, NULL);
  _tcontext_create_views(context);
  _tcontext_create_render_completes(context);

  context->swapchain_ok = true;

  /*
   * Did we get the window we asked for?
   *
   * The extent comes from the driver, not from the caller, and on Android the
   * driver can still be describing the surface as it was before the rotation.
   * Building a landscape swapchain for a portrait window is exactly what put
   * the arena in a squashed band across the top of the display with black
   * underneath — and nothing recovered from it, because a stale-but-valid
   * swapchain only reports SUBOPTIMAL, which this deliberately ignores. Saying
   * so here lets the window ask again next frame, when the driver has caught
   * up.
   */
  context->extent_stale = size[0] > 0 && size[1] > 0 &&
                          (context->size[0] != size[0] ||
                           context->size[1] != size[1]);
}

static void _tcontext_destroy_swapchain_resources(tcontext* context) {
  const uint32_t old_image_count = context->image_count;
  _tcontext_destroy_render_completes(context, old_image_count);
  if (context->swapchain_frames) {
    for (uint32_t i = 0; i < old_image_count; ++i) {
      if (context->swapchain_frames[i].framebuffer != VK_NULL_HANDLE)
        vkDestroyFramebuffer(context->device,
                             context->swapchain_frames[i].framebuffer, NULL);
      if (context->swapchain_frames[i].image_view != VK_NULL_HANDLE)
        vkDestroyImageView(context->device,
                           context->swapchain_frames[i].image_view, NULL);
    }
    free(context->swapchain_frames);
    context->swapchain_frames = NULL;
  }
  context->image_count = 0;
  if (context->swapchain != VK_NULL_HANDLE) {
    vkDestroySwapchainKHR(context->device, context->swapchain, NULL);
    context->swapchain = VK_NULL_HANDLE;
  }
  context->old_swapchain = VK_NULL_HANDLE;
}

bool tcontext_recreate_surface(tcontext* context, twindow* window, bool vsync) {
#ifndef VLITHER_ANDROID
  tcontext_resize(context, window->size, vsync);
  return context->swapchain_ok;
#else
  if (!context || !window || !window->handle) return false;
  TCONTEXT_LOG("Vlither: rebuilding Android Vulkan surface after resume");
  tcontext_wait_idle(context);
  _tcontext_destroy_swapchain_resources(context);
  if (context->surface != VK_NULL_HANDLE) {
    vkDestroySurfaceKHR(context->instance, context->surface, NULL);
    context->surface = VK_NULL_HANDLE;
  }
  if (!_tcontext_create_surface(context, window)) return false;

  VkBool32 present_supported = VK_FALSE;
  if (vkGetPhysicalDeviceSurfaceSupportKHR(
          context->ph_device, context->queue_family, context->surface,
          &present_supported) != VK_SUCCESS || !present_supported) {
    TCONTEXT_LOG("Vlither: recreated surface is not supported by graphics queue");
    return false;
  }

  uint32_t format_count = 0;
  if (vkGetPhysicalDeviceSurfaceFormatsKHR(context->ph_device, context->surface,
                                           &format_count, NULL) != VK_SUCCESS ||
      format_count == 0)
    return false;
  VkSurfaceFormatKHR* formats = calloc(format_count, sizeof(*formats));
  bool format_supported = false;
  if (formats && vkGetPhysicalDeviceSurfaceFormatsKHR(
                     context->ph_device, context->surface, &format_count,
                     formats) == VK_SUCCESS) {
    for (uint32_t i = 0; i < format_count; ++i) {
      if (formats[i].format == context->surface_format.format &&
          formats[i].colorSpace == context->surface_format.colorSpace) {
        format_supported = true;
        break;
      }
    }
  }
  free(formats);
  if (!format_supported) {
    TCONTEXT_LOG("Vlither: recreated surface changed to an incompatible format");
    return false;
  }

  context->old_swapchain = VK_NULL_HANDLE;
  context->swapchain = VK_NULL_HANDLE;
  _tcontext_create_swapchain(context, vsync);
  if (context->swapchain == VK_NULL_HANDLE) return false;
  _tcontext_create_views(context);
  _tcontext_create_render_completes(context);
  context->current_image = 0;
  context->surface_lost = false;
  context->swapchain_ok = true;
  TCONTEXT_LOG("Vlither: Android Vulkan surface restored (%dx%d, %u images)",
               context->size[0], context->size[1], context->image_count);
  return true;
#endif
}

bool tcontext_begin(tcontext* context) {
  context->last_present_succeeded = false;
  tcontext_frame* fr = context->frames + context->current_frame;
  vkWaitForFences(context->device, 1, &fr->wait_fence, VK_TRUE, UINT64_MAX);

  VkResult r = vkAcquireNextImageKHR(context->device, context->swapchain,
                                     UINT64_MAX, fr->present_complete,
                                     VK_NULL_HANDLE, &context->current_image);

  if (r == VK_ERROR_OUT_OF_DATE_KHR) {
    context->swapchain_ok = false;
    return false;
  }
  if (r == VK_ERROR_SURFACE_LOST_KHR) {
    context->surface_lost = true;
    context->swapchain_ok = false;
    TCONTEXT_LOG("Vlither: Android Vulkan surface was lost during acquire");
    return false;
  }
  if ((r != VK_SUCCESS && r != VK_SUBOPTIMAL_KHR) ||
      context->current_image >= context->image_count) {
    TCONTEXT_LOG("Vlither: vkAcquireNextImageKHR failed: %d image=%u/%u",
                 (int)r, context->current_image, context->image_count);
    return false;
  }

  vkResetFences(context->device, 1, &fr->wait_fence);

  vkResetCommandBuffer(fr->cmd, 0);
  vkBeginCommandBuffer(fr->cmd,
                       &(VkCommandBufferBeginInfo){
                           .sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO,
                           .pNext = NULL,
                           .flags = 0,
                           .pInheritanceInfo = NULL});

  return true;
}

void tcontext_clear(tcontext* context, const vec4 clear_color) {
  tcontext_frame* fr = context->frames + context->current_frame;
  _tcontext_swapchain_frame* sfr =
      context->swapchain_frames + context->current_image;

  vkCmdBeginRenderPass(
      fr->cmd,
      &(VkRenderPassBeginInfo){
          .sType = VK_STRUCTURE_TYPE_RENDER_PASS_BEGIN_INFO,
          .pNext = NULL,
          .renderPass = context->renderpass,
          .framebuffer = sfr->framebuffer,
          .renderArea = {.offset = {.x = 0, .y = 0},
                         .extent = {.width = context->size[0],
                                    .height = context->size[1]}},
          .clearValueCount = 1,
          .pClearValues =
              &(VkClearValue){
                  .color = {.float32 = {clear_color[0], clear_color[1],
                                        clear_color[2], clear_color[3]}}}},
      VK_SUBPASS_CONTENTS_INLINE);
}

void tcontext_end(tcontext* context) {
  tcontext_frame* fr = context->frames + context->current_frame;

  vkCmdEndRenderPass(fr->cmd);
  vkEndCommandBuffer(fr->cmd);

  VkResult submit_result = vkQueueSubmit(
      context->queue, 1,
      &(VkSubmitInfo){.sType = VK_STRUCTURE_TYPE_SUBMIT_INFO,
                      .pNext = NULL,
                      .waitSemaphoreCount = 1,
                      .pWaitSemaphores = &fr->present_complete,
                      .pWaitDstStageMask =
                          &(VkPipelineStageFlags){
                              VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT},
                      .commandBufferCount = 1,
                      .pCommandBuffers = &fr->cmd,
                      .signalSemaphoreCount = 1,
                      .pSignalSemaphores =
                          &context->render_completes[context->current_image]},
      fr->wait_fence);
  if (submit_result != VK_SUCCESS) {
#ifdef VLITHER_ANDROID
    char detail[96];
    snprintf(detail, sizeof(detail), "vkQueueSubmit returned %d",
             (int)submit_result);
    android_startup_failure(10, "First frame submission failed", detail);
#endif
    context->swapchain_ok = false;
    return;
  }

  VkResult r = vkQueuePresentKHR(
      context->queue,
      &(VkPresentInfoKHR){
          .sType = VK_STRUCTURE_TYPE_PRESENT_INFO_KHR,
          .pNext = NULL,
          .waitSemaphoreCount = 1,
          .pWaitSemaphores = &context->render_completes[context->current_image],
          .swapchainCount = 1,
          .pSwapchains = &context->swapchain,
          .pImageIndices = &context->current_image,
          .pResults = NULL});

  if (r == VK_ERROR_SURFACE_LOST_KHR) {
    context->surface_lost = true;
    context->swapchain_ok = false;
    TCONTEXT_LOG("Vlither: Android Vulkan surface was lost during present");
  } else if (r == VK_ERROR_OUT_OF_DATE_KHR) {
    context->swapchain_ok = false;
  } else if (r == VK_SUBOPTIMAL_KHR) {
    /* Android may continuously report SUBOPTIMAL for a valid pre-rotated
       fullscreen surface. The frame is still presented; stopping the render
       loop here freezes ImGui before it can consume queued touch events. */
    context->swapchain_ok = true;
  }
  context->last_present_succeeded =
      (r == VK_SUCCESS || r == VK_SUBOPTIMAL_KHR);
#ifdef VLITHER_ANDROID
  if (!context->last_present_succeeded && r != VK_ERROR_SURFACE_LOST_KHR &&
      r != VK_ERROR_OUT_OF_DATE_KHR) {
    char detail[96];
    snprintf(detail, sizeof(detail), "vkQueuePresentKHR returned %d", (int)r);
    android_startup_failure(10, "First frame presentation failed", detail);
  }
#endif

  context->current_frame = (context->current_frame + 1) % context->fif;
}

void tcontext_wait_idle(tcontext* context) { vkQueueWaitIdle(context->queue); }

void tcontext_destroy(tcontext* context) {
  vkDestroyDescriptorPool(context->device, context->descriptor_pool, NULL);
  vmaDestroyAllocator(context->allocator);

  vkDestroyFence(context->device, context->transfer_fence, NULL);
  vkDestroyCommandPool(context->device, context->cmd_pool, NULL);

  _tcontext_destroy_render_completes(context, context->image_count);

  for (int i = 0; i < context->fif; i++) {
    vkDestroyFence(context->device, context->frames[i].wait_fence, NULL);
    vkDestroySemaphore(context->device, context->frames[i].present_complete,
                       NULL);
  }

  free(context->frames);

  for (uint32_t i = 0; i < context->image_count; i++) {
    vkDestroyFramebuffer(context->device,
                         context->swapchain_frames[i].framebuffer, NULL);
    vkDestroyImageView(context->device, context->swapchain_frames[i].image_view,
                       NULL);
  }

  free(context->swapchain_frames);
  vkDestroyRenderPass(context->device, context->renderpass, NULL);
  vkDestroySwapchainKHR(context->device, context->swapchain, NULL);
  vkDestroyDevice(context->device, NULL);
  vkDestroySurfaceKHR(context->instance, context->surface, NULL);
  vkDestroyInstance(context->instance, NULL);

  free(context);
}
