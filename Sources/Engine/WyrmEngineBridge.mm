#define VK_ENABLE_BETA_EXTENSIONS 1
#define VK_USE_PLATFORM_METAL_EXT 1
#define SDL_MAIN_HANDLED 1

#include "WyrmEngineBridge.h"

#include <SDL3/SDL.h>
#include <SDL3/SDL_main.h>
#include <vulkan/vulkan.h>

#import <Foundation/Foundation.h>
#import <QuartzCore/CAMetalLayer.h>

#include <algorithm>
#include <cstdint>
#include <cstdio>
#include <cstring>
#include <iterator>
#include <vector>

namespace {

struct EngineState {
    bool started = false;
    VkInstance instance = VK_NULL_HANDLE;
    VkSurfaceKHR surface = VK_NULL_HANDLE;
    VkPhysicalDevice physical_device = VK_NULL_HANDLE;
    VkDevice device = VK_NULL_HANDLE;
    VkQueue queue = VK_NULL_HANDLE;
    uint32_t queue_family = UINT32_MAX;
    VkSwapchainKHR swapchain = VK_NULL_HANDLE;
    VkCommandPool command_pool = VK_NULL_HANDLE;
    VkCommandBuffer command_buffer = VK_NULL_HANDLE;
    VkSemaphore image_available = VK_NULL_HANDLE;
    VkSemaphore render_finished = VK_NULL_HANDLE;
    VkFence frame_fence = VK_NULL_HANDLE;
    std::vector<VkImage> images;
};

EngineState g_engine;
char g_status[256] = "Engine bootstrap has not started";

void set_status(const char *message) {
    std::snprintf(g_status, sizeof(g_status), "%s", message ? message : "Unknown engine status");
    NSLog(@"[WyrmEngine] %s", g_status);
}

bool fail(const char *stage, const char *detail = nullptr) {
    if (detail && detail[0] != '\0') {
        std::snprintf(g_status, sizeof(g_status), "%s: %s", stage, detail);
    } else {
        std::snprintf(g_status, sizeof(g_status), "%s", stage);
    }
    NSLog(@"[WyrmEngine] %s", g_status);
    return false;
}

bool vk_ok(VkResult result, const char *stage) {
    if (result == VK_SUCCESS) {
        return true;
    }
    std::snprintf(g_status, sizeof(g_status), "%s (VkResult %d)", stage, static_cast<int>(result));
    NSLog(@"[WyrmEngine] %s", g_status);
    return false;
}

bool has_instance_extension(const char *name) {
    uint32_t count = 0;
    if (vkEnumerateInstanceExtensionProperties(nullptr, &count, nullptr) != VK_SUCCESS) {
        return false;
    }
    std::vector<VkExtensionProperties> properties(count);
    if (vkEnumerateInstanceExtensionProperties(nullptr, &count, properties.data()) != VK_SUCCESS) {
        return false;
    }
    for (const auto &property : properties) {
        if (std::strcmp(property.extensionName, name) == 0) {
            return true;
        }
    }
    return false;
}

bool has_device_extension(VkPhysicalDevice device, const char *name) {
    uint32_t count = 0;
    if (vkEnumerateDeviceExtensionProperties(device, nullptr, &count, nullptr) != VK_SUCCESS) {
        return false;
    }
    std::vector<VkExtensionProperties> properties(count);
    if (vkEnumerateDeviceExtensionProperties(device, nullptr, &count, properties.data()) != VK_SUCCESS) {
        return false;
    }
    for (const auto &property : properties) {
        if (std::strcmp(property.extensionName, name) == 0) {
            return true;
        }
    }
    return false;
}

VkCompositeAlphaFlagBitsKHR choose_composite_alpha(VkCompositeAlphaFlagsKHR supported) {
    const VkCompositeAlphaFlagBitsKHR candidates[] = {
        VK_COMPOSITE_ALPHA_OPAQUE_BIT_KHR,
        VK_COMPOSITE_ALPHA_INHERIT_BIT_KHR,
        VK_COMPOSITE_ALPHA_PRE_MULTIPLIED_BIT_KHR,
        VK_COMPOSITE_ALPHA_POST_MULTIPLIED_BIT_KHR
    };
    for (VkCompositeAlphaFlagBitsKHR candidate : candidates) {
        if ((supported & candidate) != 0) {
            return candidate;
        }
    }
    return VK_COMPOSITE_ALPHA_OPAQUE_BIT_KHR;
}

bool create_instance() {
    const char *required[] = {
        VK_KHR_SURFACE_EXTENSION_NAME,
        VK_EXT_METAL_SURFACE_EXTENSION_NAME
    };
    for (const char *extension : required) {
        if (!has_instance_extension(extension)) {
            return fail("Required Vulkan instance extension unavailable", extension);
        }
    }

    std::vector<const char *> enabled_extensions(std::begin(required), std::end(required));
    VkInstanceCreateFlags instance_flags = 0;
    if (has_instance_extension(VK_KHR_PORTABILITY_ENUMERATION_EXTENSION_NAME)) {
        enabled_extensions.push_back(VK_KHR_PORTABILITY_ENUMERATION_EXTENSION_NAME);
        instance_flags |= VK_INSTANCE_CREATE_ENUMERATE_PORTABILITY_BIT_KHR;
        NSLog(@"[WyrmEngine] VK_KHR_portability_enumeration advertised; enabling portability discovery");
    } else {
        NSLog(@"[WyrmEngine] VK_KHR_portability_enumeration not advertised; using direct MoltenVK discovery");
    }

    VkApplicationInfo app_info{};
    app_info.sType = VK_STRUCTURE_TYPE_APPLICATION_INFO;
    app_info.pApplicationName = "Wyrm";
    app_info.applicationVersion = VK_MAKE_VERSION(0, 1, 0);
    app_info.pEngineName = "Wyrm Phase 1";
    app_info.engineVersion = VK_MAKE_VERSION(0, 1, 0);
    app_info.apiVersion = VK_API_VERSION_1_2;

    VkInstanceCreateInfo create_info{};
    create_info.sType = VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO;
    create_info.flags = instance_flags;
    create_info.pApplicationInfo = &app_info;
    create_info.enabledExtensionCount = static_cast<uint32_t>(enabled_extensions.size());
    create_info.ppEnabledExtensionNames = enabled_extensions.data();

    return vk_ok(vkCreateInstance(&create_info, nullptr, &g_engine.instance), "vkCreateInstance failed");
}

bool create_surface(CAMetalLayer *metal_layer) {
    if (!metal_layer) {
        return fail("CAMetalLayer was null");
    }

    VkMetalSurfaceCreateInfoEXT create_info{};
    create_info.sType = VK_STRUCTURE_TYPE_METAL_SURFACE_CREATE_INFO_EXT;
    create_info.pLayer = metal_layer;
    return vk_ok(
        vkCreateMetalSurfaceEXT(g_engine.instance, &create_info, nullptr, &g_engine.surface),
        "vkCreateMetalSurfaceEXT failed"
    );
}

bool choose_device_and_queue() {
    uint32_t device_count = 0;
    if (!vk_ok(vkEnumeratePhysicalDevices(g_engine.instance, &device_count, nullptr),
               "vkEnumeratePhysicalDevices failed") || device_count == 0) {
        return fail("MoltenVK exposed no Vulkan physical device");
    }

    std::vector<VkPhysicalDevice> devices(device_count);
    if (!vk_ok(vkEnumeratePhysicalDevices(g_engine.instance, &device_count, devices.data()),
               "Vulkan device enumeration failed")) {
        return false;
    }

    for (VkPhysicalDevice device : devices) {
        uint32_t queue_count = 0;
        vkGetPhysicalDeviceQueueFamilyProperties(device, &queue_count, nullptr);
        std::vector<VkQueueFamilyProperties> queues(queue_count);
        vkGetPhysicalDeviceQueueFamilyProperties(device, &queue_count, queues.data());

        for (uint32_t index = 0; index < queue_count; ++index) {
            VkBool32 can_present = VK_FALSE;
            if (vkGetPhysicalDeviceSurfaceSupportKHR(device, index, g_engine.surface, &can_present) != VK_SUCCESS) {
                continue;
            }
            if ((queues[index].queueFlags & VK_QUEUE_GRAPHICS_BIT) != 0 && can_present == VK_TRUE) {
                g_engine.physical_device = device;
                g_engine.queue_family = index;
                return true;
            }
        }
    }

    return fail("No graphics queue can present to the iPhone surface");
}

bool create_device() {
    if (!has_device_extension(g_engine.physical_device, VK_KHR_SWAPCHAIN_EXTENSION_NAME)) {
        return fail("Required Vulkan device extension unavailable", VK_KHR_SWAPCHAIN_EXTENSION_NAME);
    }

    std::vector<const char *> extensions = {VK_KHR_SWAPCHAIN_EXTENSION_NAME};
    if (has_device_extension(g_engine.physical_device, VK_KHR_PORTABILITY_SUBSET_EXTENSION_NAME)) {
        extensions.push_back(VK_KHR_PORTABILITY_SUBSET_EXTENSION_NAME);
    }

    float priority = 1.0f;
    VkDeviceQueueCreateInfo queue_info{};
    queue_info.sType = VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO;
    queue_info.queueFamilyIndex = g_engine.queue_family;
    queue_info.queueCount = 1;
    queue_info.pQueuePriorities = &priority;

    VkDeviceCreateInfo create_info{};
    create_info.sType = VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO;
    create_info.queueCreateInfoCount = 1;
    create_info.pQueueCreateInfos = &queue_info;
    create_info.enabledExtensionCount = static_cast<uint32_t>(extensions.size());
    create_info.ppEnabledExtensionNames = extensions.data();

    if (!vk_ok(vkCreateDevice(g_engine.physical_device, &create_info, nullptr, &g_engine.device),
               "vkCreateDevice failed")) {
        return false;
    }
    vkGetDeviceQueue(g_engine.device, g_engine.queue_family, 0, &g_engine.queue);
    return true;
}

bool create_swapchain(CAMetalLayer *metal_layer) {
    VkSurfaceCapabilitiesKHR capabilities{};
    if (!vk_ok(vkGetPhysicalDeviceSurfaceCapabilitiesKHR(
                   g_engine.physical_device, g_engine.surface, &capabilities),
               "Surface capabilities failed")) {
        return false;
    }
    if ((capabilities.supportedUsageFlags & VK_IMAGE_USAGE_TRANSFER_DST_BIT) == 0) {
        return fail("MoltenVK surface cannot receive the Phase 1 clear frame");
    }

    uint32_t format_count = 0;
    if (!vk_ok(vkGetPhysicalDeviceSurfaceFormatsKHR(
                   g_engine.physical_device, g_engine.surface, &format_count, nullptr),
               "Surface format count failed") || format_count == 0) {
        return fail("MoltenVK exposed no surface format");
    }
    std::vector<VkSurfaceFormatKHR> formats(format_count);
    if (!vk_ok(vkGetPhysicalDeviceSurfaceFormatsKHR(
                   g_engine.physical_device, g_engine.surface, &format_count, formats.data()),
               "Surface format enumeration failed")) {
        return false;
    }

    VkSurfaceFormatKHR chosen = formats.front();
    for (const auto &format : formats) {
        if (format.format == VK_FORMAT_B8G8R8A8_UNORM ||
            format.format == VK_FORMAT_B8G8R8A8_SRGB) {
            chosen = format;
            break;
        }
    }

    VkExtent2D extent = capabilities.currentExtent;
    if (extent.width == UINT32_MAX || extent.height == UINT32_MAX) {
        const CGSize drawable = metal_layer.drawableSize;
        extent.width = std::clamp(static_cast<uint32_t>(drawable.width),
                                  capabilities.minImageExtent.width,
                                  capabilities.maxImageExtent.width);
        extent.height = std::clamp(static_cast<uint32_t>(drawable.height),
                                   capabilities.minImageExtent.height,
                                   capabilities.maxImageExtent.height);
    }
    if (extent.width == 0 || extent.height == 0) {
        return fail("CAMetalLayer drawable size was zero");
    }

    uint32_t image_count = std::max(2u, capabilities.minImageCount);
    if (capabilities.maxImageCount > 0) {
        image_count = std::min(image_count, capabilities.maxImageCount);
    }

    VkSwapchainCreateInfoKHR create_info{};
    create_info.sType = VK_STRUCTURE_TYPE_SWAPCHAIN_CREATE_INFO_KHR;
    create_info.surface = g_engine.surface;
    create_info.minImageCount = image_count;
    create_info.imageFormat = chosen.format;
    create_info.imageColorSpace = chosen.colorSpace;
    create_info.imageExtent = extent;
    create_info.imageArrayLayers = 1;
    create_info.imageUsage = VK_IMAGE_USAGE_TRANSFER_DST_BIT;
    create_info.imageSharingMode = VK_SHARING_MODE_EXCLUSIVE;
    create_info.preTransform = capabilities.currentTransform;
    create_info.compositeAlpha = choose_composite_alpha(capabilities.supportedCompositeAlpha);
    create_info.presentMode = VK_PRESENT_MODE_FIFO_KHR;
    create_info.clipped = VK_TRUE;

    if (!vk_ok(vkCreateSwapchainKHR(g_engine.device, &create_info, nullptr, &g_engine.swapchain),
               "vkCreateSwapchainKHR failed")) {
        return false;
    }

    uint32_t actual_count = 0;
    if (!vk_ok(vkGetSwapchainImagesKHR(g_engine.device, g_engine.swapchain, &actual_count, nullptr),
               "Swapchain image count failed")) {
        return false;
    }
    g_engine.images.resize(actual_count);
    return vk_ok(vkGetSwapchainImagesKHR(
                     g_engine.device, g_engine.swapchain, &actual_count, g_engine.images.data()),
                 "Swapchain image enumeration failed");
}

bool create_frame_resources() {
    VkCommandPoolCreateInfo pool_info{};
    pool_info.sType = VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO;
    pool_info.flags = VK_COMMAND_POOL_CREATE_RESET_COMMAND_BUFFER_BIT;
    pool_info.queueFamilyIndex = g_engine.queue_family;
    if (!vk_ok(vkCreateCommandPool(g_engine.device, &pool_info, nullptr, &g_engine.command_pool),
               "vkCreateCommandPool failed")) {
        return false;
    }

    VkCommandBufferAllocateInfo buffer_info{};
    buffer_info.sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO;
    buffer_info.commandPool = g_engine.command_pool;
    buffer_info.level = VK_COMMAND_BUFFER_LEVEL_PRIMARY;
    buffer_info.commandBufferCount = 1;
    if (!vk_ok(vkAllocateCommandBuffers(g_engine.device, &buffer_info, &g_engine.command_buffer),
               "vkAllocateCommandBuffers failed")) {
        return false;
    }

    VkSemaphoreCreateInfo semaphore_info{};
    semaphore_info.sType = VK_STRUCTURE_TYPE_SEMAPHORE_CREATE_INFO;
    if (!vk_ok(vkCreateSemaphore(g_engine.device, &semaphore_info, nullptr, &g_engine.image_available),
               "Image semaphore creation failed") ||
        !vk_ok(vkCreateSemaphore(g_engine.device, &semaphore_info, nullptr, &g_engine.render_finished),
               "Render semaphore creation failed")) {
        return false;
    }

    VkFenceCreateInfo fence_info{};
    fence_info.sType = VK_STRUCTURE_TYPE_FENCE_CREATE_INFO;
    return vk_ok(vkCreateFence(g_engine.device, &fence_info, nullptr, &g_engine.frame_fence),
                 "Frame fence creation failed");
}

bool present_clear_frame() {
    uint32_t image_index = 0;
    if (!vk_ok(vkAcquireNextImageKHR(
                   g_engine.device, g_engine.swapchain, UINT64_MAX,
                   g_engine.image_available, VK_NULL_HANDLE, &image_index),
               "vkAcquireNextImageKHR failed")) {
        return false;
    }

    VkCommandBufferBeginInfo begin_info{};
    begin_info.sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO;
    begin_info.flags = VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT;
    if (!vk_ok(vkBeginCommandBuffer(g_engine.command_buffer, &begin_info),
               "vkBeginCommandBuffer failed")) {
        return false;
    }

    VkImageMemoryBarrier to_transfer{};
    to_transfer.sType = VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER;
    to_transfer.srcAccessMask = 0;
    to_transfer.dstAccessMask = VK_ACCESS_TRANSFER_WRITE_BIT;
    to_transfer.oldLayout = VK_IMAGE_LAYOUT_UNDEFINED;
    to_transfer.newLayout = VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL;
    to_transfer.srcQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED;
    to_transfer.dstQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED;
    to_transfer.image = g_engine.images[image_index];
    to_transfer.subresourceRange.aspectMask = VK_IMAGE_ASPECT_COLOR_BIT;
    to_transfer.subresourceRange.baseMipLevel = 0;
    to_transfer.subresourceRange.levelCount = 1;
    to_transfer.subresourceRange.baseArrayLayer = 0;
    to_transfer.subresourceRange.layerCount = 1;
    vkCmdPipelineBarrier(
        g_engine.command_buffer,
        VK_PIPELINE_STAGE_TOP_OF_PIPE_BIT,
        VK_PIPELINE_STAGE_TRANSFER_BIT,
        0, 0, nullptr, 0, nullptr, 1, &to_transfer
    );

    const VkClearColorValue clear = {{0.047f, 0.071f, 0.058f, 1.0f}};
    vkCmdClearColorImage(
        g_engine.command_buffer,
        g_engine.images[image_index],
        VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL,
        &clear,
        1,
        &to_transfer.subresourceRange
    );

    VkImageMemoryBarrier to_present = to_transfer;
    to_present.srcAccessMask = VK_ACCESS_TRANSFER_WRITE_BIT;
    to_present.dstAccessMask = 0;
    to_present.oldLayout = VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL;
    to_present.newLayout = VK_IMAGE_LAYOUT_PRESENT_SRC_KHR;
    vkCmdPipelineBarrier(
        g_engine.command_buffer,
        VK_PIPELINE_STAGE_TRANSFER_BIT,
        VK_PIPELINE_STAGE_BOTTOM_OF_PIPE_BIT,
        0, 0, nullptr, 0, nullptr, 1, &to_present
    );

    if (!vk_ok(vkEndCommandBuffer(g_engine.command_buffer), "vkEndCommandBuffer failed")) {
        return false;
    }

    const VkPipelineStageFlags wait_stage = VK_PIPELINE_STAGE_TRANSFER_BIT;
    VkSubmitInfo submit_info{};
    submit_info.sType = VK_STRUCTURE_TYPE_SUBMIT_INFO;
    submit_info.waitSemaphoreCount = 1;
    submit_info.pWaitSemaphores = &g_engine.image_available;
    submit_info.pWaitDstStageMask = &wait_stage;
    submit_info.commandBufferCount = 1;
    submit_info.pCommandBuffers = &g_engine.command_buffer;
    submit_info.signalSemaphoreCount = 1;
    submit_info.pSignalSemaphores = &g_engine.render_finished;
    if (!vk_ok(vkQueueSubmit(g_engine.queue, 1, &submit_info, g_engine.frame_fence),
               "vkQueueSubmit failed")) {
        return false;
    }

    VkPresentInfoKHR present_info{};
    present_info.sType = VK_STRUCTURE_TYPE_PRESENT_INFO_KHR;
    present_info.waitSemaphoreCount = 1;
    present_info.pWaitSemaphores = &g_engine.render_finished;
    present_info.swapchainCount = 1;
    present_info.pSwapchains = &g_engine.swapchain;
    present_info.pImageIndices = &image_index;
    if (!vk_ok(vkQueuePresentKHR(g_engine.queue, &present_info), "vkQueuePresentKHR failed")) {
        return false;
    }

    if (!vk_ok(vkWaitForFences(g_engine.device, 1, &g_engine.frame_fence, VK_TRUE, UINT64_MAX),
               "First-frame fence wait failed")) {
        return false;
    }
    return vk_ok(vkQueueWaitIdle(g_engine.queue), "First-frame queue wait failed");
}

}  // namespace

bool WyrmEngineBootstrap(CAMetalLayer *metal_layer) {
    if (g_engine.started) {
        return true;
    }

    set_status("Initializing SDL3");
    SDL_SetMainReady();
    if (!SDL_Init(SDL_INIT_VIDEO | SDL_INIT_EVENTS)) {
        return fail("SDL3 initialization failed", SDL_GetError());
    }

    set_status("Creating Vulkan portability instance");
    if (!create_instance() ||
        !create_surface(metal_layer) ||
        !choose_device_and_queue() ||
        !create_device() ||
        !create_swapchain(metal_layer) ||
        !create_frame_resources() ||
        !present_clear_frame()) {
        return false;
    }

    g_engine.started = true;
    set_status("SDL3 initialized · Vulkan swapchain presented through MoltenVK");
    return true;
}

const char *WyrmEngineStatus(void) {
    return g_status;
}
