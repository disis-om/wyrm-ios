#pragma once

#include <vulkan/vulkan.h>

#include <cstddef>
#include <cstdint>

struct WyrmGpuAtlas {
    VkImage image = VK_NULL_HANDLE;
    VkDeviceMemory memory = VK_NULL_HANDLE;
    VkImageView view = VK_NULL_HANDLE;
    VkSampler sampler = VK_NULL_HANDLE;
    uint32_t width = 0;
    uint32_t height = 0;
};

bool WyrmGpuAssetsUpload(VkPhysicalDevice physical_device,
                         VkDevice device,
                         VkQueue queue,
                         VkCommandBuffer command_buffer,
                         WyrmGpuAtlas *atlas,
                         char *error,
                         size_t error_capacity);

void WyrmGpuAssetsDestroy(VkDevice device, WyrmGpuAtlas *atlas);
