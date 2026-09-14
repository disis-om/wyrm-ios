#include "WyrmGpuAssets.h"

#import <Foundation/Foundation.h>
#import <ImageIO/ImageIO.h>

#include <cstdio>
#include <cstring>
#include <vector>

namespace {

bool error_at(char *out, size_t capacity, const char *stage, VkResult result = VK_SUCCESS) {
    if (result == VK_SUCCESS) {
        std::snprintf(out, capacity, "%s", stage);
    } else {
        std::snprintf(out, capacity, "%s (VkResult %d)", stage, static_cast<int>(result));
    }
    NSLog(@"[WyrmGpuAssets] %s", out);
    return false;
}

bool find_memory(VkPhysicalDevice physical_device, uint32_t type_bits,
                 VkMemoryPropertyFlags required, uint32_t *index) {
    VkPhysicalDeviceMemoryProperties properties{};
    vkGetPhysicalDeviceMemoryProperties(physical_device, &properties);
    for (uint32_t i = 0; i < properties.memoryTypeCount; ++i) {
        if ((type_bits & (1u << i)) != 0 &&
            (properties.memoryTypes[i].propertyFlags & required) == required) {
            *index = i;
            return true;
        }
    }
    return false;
}

bool check_body_shader(VkDevice device, NSString *name, char *error, size_t capacity) {
    NSURL *url = [[NSBundle mainBundle] URLForResource:name
                                         withExtension:@"spv"
                                          subdirectory:@"EngineAssets/shaders"];
    NSData *data = url ? [NSData dataWithContentsOfURL:url] : nil;
    if (!data || data.length < 20 || data.length % sizeof(uint32_t) != 0) {
        return error_at(error, capacity, "Original body shader missing or truncated");
    }
    uint32_t magic = 0;
    std::memcpy(&magic, data.bytes, sizeof(magic));
    if (magic != 0x07230203u) {
        return error_at(error, capacity, "Original body shader has invalid SPIR-V magic");
    }

    std::vector<uint32_t> words(data.length / sizeof(uint32_t));
    std::memcpy(words.data(), data.bytes, data.length);
    VkShaderModuleCreateInfo info{};
    info.sType = VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO;
    info.codeSize = data.length;
    info.pCode = words.data();
    VkShaderModule module = VK_NULL_HANDLE;
    VkResult result = vkCreateShaderModule(device, &info, nullptr, &module);
    if (result != VK_SUCCESS) {
        return error_at(error, capacity, "Original body shader module creation failed", result);
    }
    vkDestroyShaderModule(device, module, nullptr);
    return true;
}

}  // namespace

void WyrmGpuAssetsDestroy(VkDevice device, WyrmGpuAtlas *atlas) {
    if (!device || !atlas) return;
    if (atlas->sampler) vkDestroySampler(device, atlas->sampler, nullptr);
    if (atlas->view) vkDestroyImageView(device, atlas->view, nullptr);
    if (atlas->image) vkDestroyImage(device, atlas->image, nullptr);
    if (atlas->memory) vkFreeMemory(device, atlas->memory, nullptr);
    *atlas = WyrmGpuAtlas{};
}

bool WyrmGpuAssetsUpload(VkPhysicalDevice physical_device, VkDevice device,
                         VkQueue queue, VkCommandBuffer command_buffer,
                         WyrmGpuAtlas *atlas, char *error, size_t error_capacity) {
    if (!physical_device || !device || !queue || !command_buffer || !atlas || !error || !error_capacity) {
        return false;
    }

    NSURL *url = [[NSBundle mainBundle] URLForResource:@"tex_atlas_8k"
                                         withExtension:@"png"
                                          subdirectory:@"EngineAssets"];
    if (!url) return error_at(error, error_capacity, "Original Wyrm atlas not bundled");

    CGImageSourceRef source = CGImageSourceCreateWithURL((__bridge CFURLRef)url, nullptr);
    if (!source) return error_at(error, error_capacity, "Original atlas PNG could not be opened");
    CGImageRef image = CGImageSourceCreateImageAtIndex(source, 0, nullptr);
    CFRelease(source);
    if (!image) return error_at(error, error_capacity, "Original atlas PNG decode failed");

    const size_t width = CGImageGetWidth(image);
    const size_t height = CGImageGetHeight(image);
    VkPhysicalDeviceProperties gpu_properties{};
    vkGetPhysicalDeviceProperties(physical_device, &gpu_properties);
    if (!width || !height || width > gpu_properties.limits.maxImageDimension2D ||
        height > gpu_properties.limits.maxImageDimension2D ||
        width > SIZE_MAX / height / 4) {
        CGImageRelease(image);
        return error_at(error, error_capacity, "Original atlas dimensions exceed GPU limit");
    }

    const size_t byte_count = width * height * 4;
    std::vector<uint8_t> rgba(byte_count);
    CGColorSpaceRef color_space = CGColorSpaceCreateDeviceRGB();
    CGContextRef bitmap = CGBitmapContextCreate(rgba.data(), width, height, 8, width * 4,
                                                 color_space,
                                                 kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big);
    CGColorSpaceRelease(color_space);
    if (!bitmap) {
        CGImageRelease(image);
        return error_at(error, error_capacity, "Original atlas RGBA conversion failed");
    }
    CGContextDrawImage(bitmap, CGRectMake(0, 0, width, height), image);
    CGContextRelease(bitmap);
    CGImageRelease(image);

    VkBuffer staging = VK_NULL_HANDLE;
    VkDeviceMemory staging_memory = VK_NULL_HANDLE;
    auto cleanup_staging = [&]() {
        if (staging) vkDestroyBuffer(device, staging, nullptr);
        if (staging_memory) vkFreeMemory(device, staging_memory, nullptr);
    };
    auto fail_upload = [&](const char *stage, VkResult result = VK_SUCCESS) {
        cleanup_staging();
        WyrmGpuAssetsDestroy(device, atlas);
        return error_at(error, error_capacity, stage, result);
    };

    VkBufferCreateInfo buffer_info{};
    buffer_info.sType = VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO;
    buffer_info.size = byte_count;
    buffer_info.usage = VK_BUFFER_USAGE_TRANSFER_SRC_BIT;
    buffer_info.sharingMode = VK_SHARING_MODE_EXCLUSIVE;
    VkResult result = vkCreateBuffer(device, &buffer_info, nullptr, &staging);
    if (result != VK_SUCCESS) return fail_upload("Atlas staging buffer creation failed", result);

    VkMemoryRequirements requirements{};
    vkGetBufferMemoryRequirements(device, staging, &requirements);
    uint32_t memory_type = 0;
    if (!find_memory(physical_device, requirements.memoryTypeBits,
                     VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | VK_MEMORY_PROPERTY_HOST_COHERENT_BIT,
                     &memory_type)) {
        return fail_upload("No coherent host memory for atlas upload");
    }
    VkMemoryAllocateInfo allocation{};
    allocation.sType = VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO;
    allocation.allocationSize = requirements.size;
    allocation.memoryTypeIndex = memory_type;
    result = vkAllocateMemory(device, &allocation, nullptr, &staging_memory);
    if (result != VK_SUCCESS) return fail_upload("Atlas staging allocation failed", result);
    result = vkBindBufferMemory(device, staging, staging_memory, 0);
    if (result != VK_SUCCESS) return fail_upload("Atlas staging bind failed", result);

    void *mapped = nullptr;
    result = vkMapMemory(device, staging_memory, 0, byte_count, 0, &mapped);
    if (result != VK_SUCCESS) return fail_upload("Atlas staging map failed", result);
    std::memcpy(mapped, rgba.data(), byte_count);
    vkUnmapMemory(device, staging_memory);
    rgba.clear();
    rgba.shrink_to_fit();

    VkImageCreateInfo image_info{};
    image_info.sType = VK_STRUCTURE_TYPE_IMAGE_CREATE_INFO;
    image_info.imageType = VK_IMAGE_TYPE_2D;
    image_info.format = VK_FORMAT_R8G8B8A8_UNORM;
    image_info.extent = {static_cast<uint32_t>(width), static_cast<uint32_t>(height), 1};
    image_info.mipLevels = 1;
    image_info.arrayLayers = 1;
    image_info.samples = VK_SAMPLE_COUNT_1_BIT;
    image_info.tiling = VK_IMAGE_TILING_OPTIMAL;
    image_info.usage = VK_IMAGE_USAGE_TRANSFER_DST_BIT | VK_IMAGE_USAGE_SAMPLED_BIT;
    image_info.sharingMode = VK_SHARING_MODE_EXCLUSIVE;
    image_info.initialLayout = VK_IMAGE_LAYOUT_UNDEFINED;
    result = vkCreateImage(device, &image_info, nullptr, &atlas->image);
    if (result != VK_SUCCESS) return fail_upload("Atlas GPU image creation failed", result);

    vkGetImageMemoryRequirements(device, atlas->image, &requirements);
    if (!find_memory(physical_device, requirements.memoryTypeBits,
                     VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT, &memory_type) &&
        !find_memory(physical_device, requirements.memoryTypeBits, 0, &memory_type)) {
        return fail_upload("No compatible GPU memory for atlas");
    }
    allocation.allocationSize = requirements.size;
    allocation.memoryTypeIndex = memory_type;
    result = vkAllocateMemory(device, &allocation, nullptr, &atlas->memory);
    if (result != VK_SUCCESS) return fail_upload("Atlas GPU memory allocation failed", result);
    result = vkBindImageMemory(device, atlas->image, atlas->memory, 0);
    if (result != VK_SUCCESS) return fail_upload("Atlas GPU memory bind failed", result);

    result = vkResetCommandBuffer(command_buffer, 0);
    if (result != VK_SUCCESS) return fail_upload("Atlas upload command reset failed", result);
    VkCommandBufferBeginInfo begin{};
    begin.sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO;
    begin.flags = VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT;
    result = vkBeginCommandBuffer(command_buffer, &begin);
    if (result != VK_SUCCESS) return fail_upload("Atlas upload command begin failed", result);

    VkImageMemoryBarrier barrier{};
    barrier.sType = VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER;
    barrier.srcAccessMask = 0;
    barrier.dstAccessMask = VK_ACCESS_TRANSFER_WRITE_BIT;
    barrier.oldLayout = VK_IMAGE_LAYOUT_UNDEFINED;
    barrier.newLayout = VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL;
    barrier.srcQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED;
    barrier.dstQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED;
    barrier.image = atlas->image;
    barrier.subresourceRange = {VK_IMAGE_ASPECT_COLOR_BIT, 0, 1, 0, 1};
    vkCmdPipelineBarrier(command_buffer, VK_PIPELINE_STAGE_TOP_OF_PIPE_BIT,
                         VK_PIPELINE_STAGE_TRANSFER_BIT, 0, 0, nullptr, 0, nullptr, 1, &barrier);

    VkBufferImageCopy copy{};
    copy.imageSubresource = {VK_IMAGE_ASPECT_COLOR_BIT, 0, 0, 1};
    copy.imageExtent = {static_cast<uint32_t>(width), static_cast<uint32_t>(height), 1};
    vkCmdCopyBufferToImage(command_buffer, staging, atlas->image,
                           VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL, 1, &copy);

    barrier.srcAccessMask = VK_ACCESS_TRANSFER_WRITE_BIT;
    barrier.dstAccessMask = VK_ACCESS_SHADER_READ_BIT;
    barrier.oldLayout = VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL;
    barrier.newLayout = VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL;
    vkCmdPipelineBarrier(command_buffer, VK_PIPELINE_STAGE_TRANSFER_BIT,
                         VK_PIPELINE_STAGE_FRAGMENT_SHADER_BIT, 0, 0, nullptr, 0, nullptr, 1, &barrier);
    result = vkEndCommandBuffer(command_buffer);
    if (result != VK_SUCCESS) return fail_upload("Atlas upload command end failed", result);

    VkSubmitInfo submit{};
    submit.sType = VK_STRUCTURE_TYPE_SUBMIT_INFO;
    submit.commandBufferCount = 1;
    submit.pCommandBuffers = &command_buffer;
    result = vkQueueSubmit(queue, 1, &submit, VK_NULL_HANDLE);
    if (result != VK_SUCCESS) return fail_upload("Atlas GPU upload submit failed", result);
    result = vkQueueWaitIdle(queue);
    if (result != VK_SUCCESS) return fail_upload("Atlas GPU upload wait failed", result);
    cleanup_staging();
    staging = VK_NULL_HANDLE;
    staging_memory = VK_NULL_HANDLE;

    VkImageViewCreateInfo view_info{};
    view_info.sType = VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO;
    view_info.image = atlas->image;
    view_info.viewType = VK_IMAGE_VIEW_TYPE_2D;
    view_info.format = VK_FORMAT_R8G8B8A8_UNORM;
    view_info.subresourceRange = {VK_IMAGE_ASPECT_COLOR_BIT, 0, 1, 0, 1};
    result = vkCreateImageView(device, &view_info, nullptr, &atlas->view);
    if (result != VK_SUCCESS) return fail_upload("Atlas image view creation failed", result);

    VkSamplerCreateInfo sampler_info{};
    sampler_info.sType = VK_STRUCTURE_TYPE_SAMPLER_CREATE_INFO;
    sampler_info.magFilter = VK_FILTER_LINEAR;
    sampler_info.minFilter = VK_FILTER_LINEAR;
    sampler_info.mipmapMode = VK_SAMPLER_MIPMAP_MODE_NEAREST;
    sampler_info.addressModeU = VK_SAMPLER_ADDRESS_MODE_CLAMP_TO_EDGE;
    sampler_info.addressModeV = VK_SAMPLER_ADDRESS_MODE_CLAMP_TO_EDGE;
    sampler_info.addressModeW = VK_SAMPLER_ADDRESS_MODE_CLAMP_TO_EDGE;
    sampler_info.maxLod = 0;
    result = vkCreateSampler(device, &sampler_info, nullptr, &atlas->sampler);
    if (result != VK_SUCCESS) return fail_upload("Atlas sampler creation failed", result);

    if (!check_body_shader(device, @"bpv", error, error_capacity) ||
        !check_body_shader(device, @"bpf", error, error_capacity)) {
        WyrmGpuAssetsDestroy(device, atlas);
        return false;
    }

    atlas->width = static_cast<uint32_t>(width);
    atlas->height = static_cast<uint32_t>(height);
    std::snprintf(error, error_capacity,
                  "Original %ux%u Wyrm atlas uploaded to GPU; body shaders accepted",
                  atlas->width, atlas->height);
    NSLog(@"[WyrmGpuAssets] %s", error);
    return true;
}
