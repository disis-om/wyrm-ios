#include "WyrmBodyPreview.h"

#import <Foundation/Foundation.h>

#include <algorithm>
#include <cstdio>
#include <cstring>
#include <vector>

namespace {

struct Resources {
    VkDevice device;
    VkQueue queue;
    bool submitted = false;
    VkRenderPass pass = VK_NULL_HANDLE;
    VkDescriptorSetLayout descriptors = VK_NULL_HANDLE;
    VkDescriptorPool descriptor_pool = VK_NULL_HANDLE;
    VkPipelineLayout pipeline_layout = VK_NULL_HANDLE;
    VkPipeline pipeline = VK_NULL_HANDLE;
    VkShaderModule vertex_shader = VK_NULL_HANDLE;
    VkShaderModule fragment_shader = VK_NULL_HANDLE;
    VkBuffer vertices = VK_NULL_HANDLE;
    VkDeviceMemory vertex_memory = VK_NULL_HANDLE;
    VkBuffer uniform = VK_NULL_HANDLE;
    VkDeviceMemory uniform_memory = VK_NULL_HANDLE;
    VkImageView target_view = VK_NULL_HANDLE;
    VkFramebuffer framebuffer = VK_NULL_HANDLE;

    ~Resources() {
        if (submitted) vkQueueWaitIdle(queue);
        if (framebuffer) vkDestroyFramebuffer(device, framebuffer, nullptr);
        if (target_view) vkDestroyImageView(device, target_view, nullptr);
        if (pipeline) vkDestroyPipeline(device, pipeline, nullptr);
        if (pipeline_layout) vkDestroyPipelineLayout(device, pipeline_layout, nullptr);
        if (descriptor_pool) vkDestroyDescriptorPool(device, descriptor_pool, nullptr);
        if (descriptors) vkDestroyDescriptorSetLayout(device, descriptors, nullptr);
        if (vertex_shader) vkDestroyShaderModule(device, vertex_shader, nullptr);
        if (fragment_shader) vkDestroyShaderModule(device, fragment_shader, nullptr);
        if (pass) vkDestroyRenderPass(device, pass, nullptr);
        if (vertices) vkDestroyBuffer(device, vertices, nullptr);
        if (vertex_memory) vkFreeMemory(device, vertex_memory, nullptr);
        if (uniform) vkDestroyBuffer(device, uniform, nullptr);
        if (uniform_memory) vkFreeMemory(device, uniform_memory, nullptr);
    }
};

bool fail(char *out, size_t capacity, const char *stage, VkResult result = VK_SUCCESS) {
    if (result == VK_SUCCESS) std::snprintf(out, capacity, "%s", stage);
    else std::snprintf(out, capacity, "%s (VkResult %d)", stage, static_cast<int>(result));
    NSLog(@"[WyrmBodyPreview] %s", out);
    return false;
}

bool check(VkResult result, char *out, size_t capacity, const char *stage) {
    return result == VK_SUCCESS || fail(out, capacity, stage, result);
}

bool shader(VkDevice device, NSString *name, VkShaderModule *module,
            char *out, size_t capacity) {
    NSURL *url = [[NSBundle mainBundle] URLForResource:name withExtension:@"spv"
                                           subdirectory:@"EngineAssets/shaders"];
    NSData *data = url ? [NSData dataWithContentsOfURL:url] : nil;
    if (!data || data.length < 20 || data.length % 4 != 0)
        return fail(out, capacity, "Original body shader unavailable");
    std::vector<uint32_t> words(data.length / 4);
    std::memcpy(words.data(), data.bytes, data.length);
    if (words[0] != 0x07230203u) return fail(out, capacity, "Invalid original body SPIR-V");
    VkShaderModuleCreateInfo info{};
    info.sType = VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO;
    info.codeSize = data.length;
    info.pCode = words.data();
    return check(vkCreateShaderModule(device, &info, nullptr, module),
                 out, capacity, "Body shader module creation failed");
}

bool buffer(VkPhysicalDevice physical, VkDevice device, VkDeviceSize size,
            VkBufferUsageFlags usage, const void *data, VkBuffer *handle,
            VkDeviceMemory *memory, char *out, size_t capacity) {
    VkBufferCreateInfo info{};
    info.sType = VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO;
    info.size = size;
    info.usage = usage;
    info.sharingMode = VK_SHARING_MODE_EXCLUSIVE;
    if (!check(vkCreateBuffer(device, &info, nullptr, handle), out, capacity,
               "Body buffer creation failed")) return false;
    VkMemoryRequirements requirements{};
    vkGetBufferMemoryRequirements(device, *handle, &requirements);
    VkPhysicalDeviceMemoryProperties properties{};
    vkGetPhysicalDeviceMemoryProperties(physical, &properties);
    uint32_t index = UINT32_MAX;
    for (uint32_t i = 0; i < properties.memoryTypeCount; ++i) {
        if ((requirements.memoryTypeBits & (1u << i)) &&
            (properties.memoryTypes[i].propertyFlags &
             (VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | VK_MEMORY_PROPERTY_HOST_COHERENT_BIT)) ==
             (VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | VK_MEMORY_PROPERTY_HOST_COHERENT_BIT)) {
            index = i;
            break;
        }
    }
    if (index == UINT32_MAX) return fail(out, capacity, "No coherent memory for body buffers");
    VkMemoryAllocateInfo allocation{};
    allocation.sType = VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO;
    allocation.allocationSize = requirements.size;
    allocation.memoryTypeIndex = index;
    if (!check(vkAllocateMemory(device, &allocation, nullptr, memory), out, capacity,
               "Body buffer allocation failed") ||
        !check(vkBindBufferMemory(device, *handle, *memory, 0), out, capacity,
               "Body buffer memory binding failed")) return false;
    void *mapped = nullptr;
    if (!check(vkMapMemory(device, *memory, 0, size, 0, &mapped), out, capacity,
               "Body buffer mapping failed")) return false;
    std::memcpy(mapped, data, static_cast<size_t>(size));
    vkUnmapMemory(device, *memory);
    return true;
}

}  // namespace

bool WyrmBodyPreviewPresent(VkPhysicalDevice physical, VkDevice device, VkQueue queue,
                            VkSwapchainKHR swapchain, VkFormat format, VkExtent2D extent,
                            VkCommandBuffer command, VkSemaphore acquired, VkSemaphore rendered,
                            VkFence fence, const WyrmGpuAtlas &atlas,
                            char *status, size_t capacity) {
    if (!physical || !device || !queue || !swapchain || !command || !status || !capacity ||
        !atlas.view || !atlas.sampler || atlas.width != 3136 || atlas.height != 4032)
        return fail(status, capacity, "Body preview prerequisites missing");
    Resources r{device, queue};
    if (!shader(device, @"bpv", &r.vertex_shader, status, capacity) ||
        !shader(device, @"bpf", &r.fragment_shader, status, capacity)) return false;

    // Original bp.slang: binding 0 is Global.viewport, binding 1 is tex_atlas.
    VkDescriptorSetLayoutBinding bindings[2]{};
    bindings[0] = {0, VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER, 1, VK_SHADER_STAGE_VERTEX_BIT, nullptr};
    bindings[1] = {1, VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER, 1,
                   VK_SHADER_STAGE_FRAGMENT_BIT, nullptr};
    VkDescriptorSetLayoutCreateInfo descriptor_info{};
    descriptor_info.sType = VK_STRUCTURE_TYPE_DESCRIPTOR_SET_LAYOUT_CREATE_INFO;
    descriptor_info.bindingCount = 2;
    descriptor_info.pBindings = bindings;
    if (!check(vkCreateDescriptorSetLayout(device, &descriptor_info, nullptr, &r.descriptors),
               status, capacity, "Body descriptor layout failed")) return false;
    VkDescriptorPoolSize pool_sizes[2] = {{VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER, 1},
                                          {VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER, 1}};
    VkDescriptorPoolCreateInfo pool_info{};
    pool_info.sType = VK_STRUCTURE_TYPE_DESCRIPTOR_POOL_CREATE_INFO;
    pool_info.maxSets = 1;
    pool_info.poolSizeCount = 2;
    pool_info.pPoolSizes = pool_sizes;
    if (!check(vkCreateDescriptorPool(device, &pool_info, nullptr, &r.descriptor_pool),
               status, capacity, "Body descriptor pool failed")) return false;
    VkDescriptorSetAllocateInfo set_info{};
    set_info.sType = VK_STRUCTURE_TYPE_DESCRIPTOR_SET_ALLOCATE_INFO;
    set_info.descriptorPool = r.descriptor_pool;
    set_info.descriptorSetCount = 1;
    set_info.pSetLayouts = &r.descriptors;
    VkDescriptorSet set = VK_NULL_HANDLE;
    if (!check(vkAllocateDescriptorSets(device, &set_info, &set),
               status, capacity, "Body descriptor allocation failed")) return false;

    // Match Android bp_renderer.c's vertex quad and one 3xvec4 bead instance.
    const float side = std::min(extent.width * 0.4f, extent.height * 0.25f);
    const float quad[8] = {0, 0, 0, 1, 1, 0, 1, 1};
    const float instance[12] = {
        (extent.width - side) * 0.5f, (extent.height - side) * 0.5f, side, 0,
        3.0f / 7.0f, 4.0f / 9.0f, 1.0f / 7.0f, 1.0f / 9.0f,
        1, 1, 1, 1
    };
    uint8_t vertex_data[sizeof(quad) + sizeof(instance)];
    std::memcpy(vertex_data, quad, sizeof(quad));
    std::memcpy(vertex_data + sizeof(quad), instance, sizeof(instance));
    if (!buffer(physical, device, sizeof(vertex_data), VK_BUFFER_USAGE_VERTEX_BUFFER_BIT,
                vertex_data, &r.vertices, &r.vertex_memory, status, capacity)) return false;
    float globals[64]{};
    globals[0] = static_cast<float>(extent.width);
    globals[1] = static_cast<float>(extent.height);
    if (!buffer(physical, device, sizeof(globals), VK_BUFFER_USAGE_UNIFORM_BUFFER_BIT,
                globals, &r.uniform, &r.uniform_memory, status, capacity)) return false;
    VkDescriptorBufferInfo uniform_info{r.uniform, 0, sizeof(globals)};
    VkDescriptorImageInfo image_info{atlas.sampler, atlas.view,
                                     VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL};
    VkWriteDescriptorSet writes[2]{};
    for (int i = 0; i < 2; ++i) {
        writes[i].sType = VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET;
        writes[i].dstSet = set;
        writes[i].dstBinding = static_cast<uint32_t>(i);
        writes[i].descriptorCount = 1;
    }
    writes[0].descriptorType = VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER;
    writes[0].pBufferInfo = &uniform_info;
    writes[1].descriptorType = VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER;
    writes[1].pImageInfo = &image_info;
    vkUpdateDescriptorSets(device, 2, writes, 0, nullptr);

    VkAttachmentDescription attachment{};
    attachment.format = format;
    attachment.samples = VK_SAMPLE_COUNT_1_BIT;
    attachment.loadOp = VK_ATTACHMENT_LOAD_OP_CLEAR;
    attachment.storeOp = VK_ATTACHMENT_STORE_OP_STORE;
    attachment.stencilLoadOp = VK_ATTACHMENT_LOAD_OP_DONT_CARE;
    attachment.stencilStoreOp = VK_ATTACHMENT_STORE_OP_DONT_CARE;
    attachment.initialLayout = VK_IMAGE_LAYOUT_UNDEFINED;
    attachment.finalLayout = VK_IMAGE_LAYOUT_PRESENT_SRC_KHR;
    VkAttachmentReference color_ref{0, VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL};
    VkSubpassDescription subpass{};
    subpass.pipelineBindPoint = VK_PIPELINE_BIND_POINT_GRAPHICS;
    subpass.colorAttachmentCount = 1;
    subpass.pColorAttachments = &color_ref;
    VkSubpassDependency dependency{};
    dependency.srcSubpass = VK_SUBPASS_EXTERNAL;
    dependency.dstSubpass = 0;
    dependency.srcStageMask = VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT;
    dependency.dstStageMask = VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT;
    dependency.dstAccessMask = VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT;
    VkRenderPassCreateInfo pass_info{};
    pass_info.sType = VK_STRUCTURE_TYPE_RENDER_PASS_CREATE_INFO;
    pass_info.attachmentCount = 1;
    pass_info.pAttachments = &attachment;
    pass_info.subpassCount = 1;
    pass_info.pSubpasses = &subpass;
    pass_info.dependencyCount = 1;
    pass_info.pDependencies = &dependency;
    if (!check(vkCreateRenderPass(device, &pass_info, nullptr, &r.pass),
               status, capacity, "Body render pass failed")) return false;
    VkPipelineLayoutCreateInfo layout_info{};
    layout_info.sType = VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO;
    layout_info.setLayoutCount = 1;
    layout_info.pSetLayouts = &r.descriptors;
    if (!check(vkCreatePipelineLayout(device, &layout_info, nullptr, &r.pipeline_layout),
               status, capacity, "Body pipeline layout failed")) return false;

    VkPipelineShaderStageCreateInfo stages[2]{};
    stages[0].sType = VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO;
    stages[0].stage = VK_SHADER_STAGE_VERTEX_BIT;
    stages[0].module = r.vertex_shader;
    stages[0].pName = "main";
    stages[1] = stages[0];
    stages[1].stage = VK_SHADER_STAGE_FRAGMENT_BIT;
    stages[1].module = r.fragment_shader;
    VkVertexInputBindingDescription vertex_bindings[2] = {{0, 8, VK_VERTEX_INPUT_RATE_VERTEX},
                                                            {1, 48, VK_VERTEX_INPUT_RATE_INSTANCE}};
    VkVertexInputAttributeDescription attributes[4] = {
        {0, 0, VK_FORMAT_R32G32_SFLOAT, 0},
        {1, 1, VK_FORMAT_R32G32B32A32_SFLOAT, 0},
        {2, 1, VK_FORMAT_R32G32B32A32_SFLOAT, 16},
        {3, 1, VK_FORMAT_R32G32B32A32_SFLOAT, 32}
    };
    VkPipelineVertexInputStateCreateInfo vertex_input{};
    vertex_input.sType = VK_STRUCTURE_TYPE_PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO;
    vertex_input.vertexBindingDescriptionCount = 2;
    vertex_input.pVertexBindingDescriptions = vertex_bindings;
    vertex_input.vertexAttributeDescriptionCount = 4;
    vertex_input.pVertexAttributeDescriptions = attributes;
    VkPipelineInputAssemblyStateCreateInfo assembly{};
    assembly.sType = VK_STRUCTURE_TYPE_PIPELINE_INPUT_ASSEMBLY_STATE_CREATE_INFO;
    assembly.topology = VK_PRIMITIVE_TOPOLOGY_TRIANGLE_STRIP;
    VkPipelineViewportStateCreateInfo viewport_state{};
    viewport_state.sType = VK_STRUCTURE_TYPE_PIPELINE_VIEWPORT_STATE_CREATE_INFO;
    viewport_state.viewportCount = 1;
    viewport_state.scissorCount = 1;
    VkPipelineRasterizationStateCreateInfo raster{};
    raster.sType = VK_STRUCTURE_TYPE_PIPELINE_RASTERIZATION_STATE_CREATE_INFO;
    raster.polygonMode = VK_POLYGON_MODE_FILL;
    raster.cullMode = VK_CULL_MODE_NONE;
    raster.frontFace = VK_FRONT_FACE_COUNTER_CLOCKWISE;
    raster.lineWidth = 1;
    VkPipelineMultisampleStateCreateInfo multisample{};
    multisample.sType = VK_STRUCTURE_TYPE_PIPELINE_MULTISAMPLE_STATE_CREATE_INFO;
    multisample.rasterizationSamples = VK_SAMPLE_COUNT_1_BIT;
    VkPipelineColorBlendAttachmentState blend{};
    blend.blendEnable = VK_TRUE;
    blend.srcColorBlendFactor = VK_BLEND_FACTOR_SRC_ALPHA;
    blend.dstColorBlendFactor = VK_BLEND_FACTOR_ONE_MINUS_SRC_ALPHA;
    blend.colorBlendOp = VK_BLEND_OP_ADD;
    blend.srcAlphaBlendFactor = VK_BLEND_FACTOR_ONE;
    blend.dstAlphaBlendFactor = VK_BLEND_FACTOR_ONE_MINUS_SRC_ALPHA;
    blend.alphaBlendOp = VK_BLEND_OP_ADD;
    blend.colorWriteMask = VK_COLOR_COMPONENT_R_BIT | VK_COLOR_COMPONENT_G_BIT |
                           VK_COLOR_COMPONENT_B_BIT | VK_COLOR_COMPONENT_A_BIT;
    VkPipelineColorBlendStateCreateInfo blend_state{};
    blend_state.sType = VK_STRUCTURE_TYPE_PIPELINE_COLOR_BLEND_STATE_CREATE_INFO;
    blend_state.attachmentCount = 1;
    blend_state.pAttachments = &blend;
    VkDynamicState dynamic_states[2] = {VK_DYNAMIC_STATE_VIEWPORT, VK_DYNAMIC_STATE_SCISSOR};
    VkPipelineDynamicStateCreateInfo dynamic{};
    dynamic.sType = VK_STRUCTURE_TYPE_PIPELINE_DYNAMIC_STATE_CREATE_INFO;
    dynamic.dynamicStateCount = 2;
    dynamic.pDynamicStates = dynamic_states;
    VkGraphicsPipelineCreateInfo pipeline_info{};
    pipeline_info.sType = VK_STRUCTURE_TYPE_GRAPHICS_PIPELINE_CREATE_INFO;
    pipeline_info.stageCount = 2;
    pipeline_info.pStages = stages;
    pipeline_info.pVertexInputState = &vertex_input;
    pipeline_info.pInputAssemblyState = &assembly;
    pipeline_info.pViewportState = &viewport_state;
    pipeline_info.pRasterizationState = &raster;
    pipeline_info.pMultisampleState = &multisample;
    pipeline_info.pColorBlendState = &blend_state;
    pipeline_info.pDynamicState = &dynamic;
    pipeline_info.layout = r.pipeline_layout;
    pipeline_info.renderPass = r.pass;
    if (!check(vkCreateGraphicsPipelines(device, VK_NULL_HANDLE, 1, &pipeline_info,
                                         nullptr, &r.pipeline), status, capacity,
               "Original body graphics pipeline failed")) return false;

    uint32_t image_index = 0;
    if (!check(vkAcquireNextImageKHR(device, swapchain, UINT64_MAX, acquired, VK_NULL_HANDLE,
                                     &image_index), status, capacity,
               "Body frame acquire failed")) return false;
    uint32_t image_count = 0;
    if (!check(vkGetSwapchainImagesKHR(device, swapchain, &image_count, nullptr),
               status, capacity, "Body swapchain count failed") || image_index >= image_count)
        return fail(status, capacity, "Body swapchain index invalid");
    std::vector<VkImage> images(image_count);
    if (!check(vkGetSwapchainImagesKHR(device, swapchain, &image_count, images.data()),
               status, capacity, "Body swapchain images failed")) return false;
    VkImageViewCreateInfo view_info{};
    view_info.sType = VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO;
    view_info.image = images[image_index];
    view_info.viewType = VK_IMAGE_VIEW_TYPE_2D;
    view_info.format = format;
    view_info.subresourceRange = {VK_IMAGE_ASPECT_COLOR_BIT, 0, 1, 0, 1};
    if (!check(vkCreateImageView(device, &view_info, nullptr, &r.target_view),
               status, capacity, "Body target view failed")) return false;
    VkFramebufferCreateInfo frame_info{};
    frame_info.sType = VK_STRUCTURE_TYPE_FRAMEBUFFER_CREATE_INFO;
    frame_info.renderPass = r.pass;
    frame_info.attachmentCount = 1;
    frame_info.pAttachments = &r.target_view;
    frame_info.width = extent.width;
    frame_info.height = extent.height;
    frame_info.layers = 1;
    if (!check(vkCreateFramebuffer(device, &frame_info, nullptr, &r.framebuffer),
               status, capacity, "Body framebuffer failed")) return false;
    if (!check(vkResetCommandBuffer(command, 0), status, capacity,
               "Body command reset failed")) return false;
    VkCommandBufferBeginInfo begin{};
    begin.sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO;
    begin.flags = VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT;
    if (!check(vkBeginCommandBuffer(command, &begin), status, capacity,
               "Body command begin failed")) return false;
    VkClearValue clear{};
    clear.color = {{0.047f, 0.071f, 0.058f, 1.0f}};
    VkRenderPassBeginInfo render_begin{};
    render_begin.sType = VK_STRUCTURE_TYPE_RENDER_PASS_BEGIN_INFO;
    render_begin.renderPass = r.pass;
    render_begin.framebuffer = r.framebuffer;
    render_begin.renderArea = {{0, 0}, extent};
    render_begin.clearValueCount = 1;
    render_begin.pClearValues = &clear;
    vkCmdBeginRenderPass(command, &render_begin, VK_SUBPASS_CONTENTS_INLINE);
    VkViewport viewport{0, 0, static_cast<float>(extent.width),
                        static_cast<float>(extent.height), 0, 1};
    VkRect2D scissor{{0, 0}, extent};
    vkCmdSetViewport(command, 0, 1, &viewport);
    vkCmdSetScissor(command, 0, 1, &scissor);
    vkCmdBindPipeline(command, VK_PIPELINE_BIND_POINT_GRAPHICS, r.pipeline);
    vkCmdBindDescriptorSets(command, VK_PIPELINE_BIND_POINT_GRAPHICS, r.pipeline_layout,
                            0, 1, &set, 0, nullptr);
    VkBuffer vertex_buffers[2] = {r.vertices, r.vertices};
    VkDeviceSize offsets[2] = {0, sizeof(quad)};
    vkCmdBindVertexBuffers(command, 0, 2, vertex_buffers, offsets);
    vkCmdDraw(command, 4, 1, 0, 0);
    vkCmdEndRenderPass(command);
    if (!check(vkEndCommandBuffer(command), status, capacity,
               "Body command end failed")) return false;
    VkPipelineStageFlags wait_stage = VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT;
    VkSubmitInfo submit{};
    submit.sType = VK_STRUCTURE_TYPE_SUBMIT_INFO;
    submit.waitSemaphoreCount = 1;
    submit.pWaitSemaphores = &acquired;
    submit.pWaitDstStageMask = &wait_stage;
    submit.commandBufferCount = 1;
    submit.pCommandBuffers = &command;
    submit.signalSemaphoreCount = 1;
    submit.pSignalSemaphores = &rendered;
    if (!check(vkResetFences(device, 1, &fence), status, capacity,
               "Body fence reset failed") ||
        !check(vkQueueSubmit(queue, 1, &submit, fence), status, capacity,
               "Body queue submit failed")) return false;
    r.submitted = true;
    VkPresentInfoKHR present{};
    present.sType = VK_STRUCTURE_TYPE_PRESENT_INFO_KHR;
    present.waitSemaphoreCount = 1;
    present.pWaitSemaphores = &rendered;
    present.swapchainCount = 1;
    present.pSwapchains = &swapchain;
    present.pImageIndices = &image_index;
    if (!check(vkQueuePresentKHR(queue, &present), status, capacity,
               "Body frame presentation failed") ||
        !check(vkWaitForFences(device, 1, &fence, VK_TRUE, UINT64_MAX), status, capacity,
               "Body frame fence wait failed") ||
        !check(vkQueueWaitIdle(queue), status, capacity,
               "Body frame queue wait failed")) return false;
    r.submitted = false;
    std::snprintf(status, capacity, "Original Wyrm body shader frame presented through Vulkan");
    NSLog(@"[WyrmBodyPreview] %s", status);
    return true;
}
