#pragma once

#include "WyrmGpuAssets.h"

#include <cstddef>

bool WyrmBodyPreviewPresent(VkPhysicalDevice physical, VkDevice device, VkQueue queue,
                            VkSwapchainKHR swapchain, VkFormat format, VkExtent2D extent,
                            VkCommandBuffer command, VkSemaphore acquired, VkSemaphore rendered,
                            VkFence fence, const WyrmGpuAtlas &atlas,
                            char *status, size_t status_capacity);
