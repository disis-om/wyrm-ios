#include <string.h>

#include "../game/backgrounds.h"
#include "../user.h"
#ifdef VLITHER_ANDROID
#include "../platform/android_startup.h"
#endif

#define BACKGROUND_LOGICAL_WIDTH 4096.0f
#define BACKGROUND_LOGICAL_HEIGHT 3548.0f

void _create_image_data(renderer* r, tcontext* ctx, ivec2 size) {
  glm_ivec2_copy(size, r->size);
  for (int i = 0; i < ctx->fif; i++) {
    vmaCreateImage(
        ctx->allocator,
        &(VkImageCreateInfo){
            .sType = VK_STRUCTURE_TYPE_IMAGE_CREATE_INFO,
            .pNext = NULL,
            .flags = 0,
            .imageType = VK_IMAGE_TYPE_2D,
            .format = VK_FORMAT_R8G8B8A8_UNORM,
            .extent = {.width = size[0], .height = size[1], .depth = 1},
            .mipLevels = 1,
            .arrayLayers = 1,
            .samples = VK_SAMPLE_COUNT_1_BIT,
            .tiling = VK_IMAGE_TILING_OPTIMAL,
            .usage = VK_IMAGE_USAGE_SAMPLED_BIT |
                     VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT,
            .sharingMode = VK_SHARING_MODE_EXCLUSIVE,
            .queueFamilyIndexCount = 0,
            .pQueueFamilyIndices = NULL,
            .initialLayout = VK_IMAGE_LAYOUT_UNDEFINED},
        &(VmaAllocationCreateInfo){
            .flags = VMA_ALLOCATION_CREATE_DEDICATED_MEMORY_BIT,
            .usage = VMA_MEMORY_USAGE_AUTO,
            .priority = 1.0f},
        &r->images[i].color, &r->images[i].memory, NULL);
    vkCreateImageView(
        ctx->device,
        &(VkImageViewCreateInfo){
            .sType = VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO,
            .pNext = NULL,
            .flags = 0,
            .image = r->images[i].color,
            .viewType = VK_IMAGE_VIEW_TYPE_2D,
            .format = VK_FORMAT_R8G8B8A8_UNORM,
            .components = {.r = VK_COMPONENT_SWIZZLE_IDENTITY,
                           .g = VK_COMPONENT_SWIZZLE_IDENTITY,
                           .b = VK_COMPONENT_SWIZZLE_IDENTITY,
                           .a = VK_COMPONENT_SWIZZLE_IDENTITY},
            .subresourceRange = {.aspectMask = VK_IMAGE_ASPECT_COLOR_BIT,
                                 .baseMipLevel = 0,
                                 .levelCount = 1,
                                 .baseArrayLayer = 0,
                                 .layerCount = 1}},
        NULL, &r->images[i].color_view);

    vkCreateImageView(
        ctx->device,
        &(VkImageViewCreateInfo){
            .sType = VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO,
            .pNext = NULL,
            .flags = 0,
            .image = r->images[i].color,
            .viewType = VK_IMAGE_VIEW_TYPE_2D,
            .format = VK_FORMAT_R8G8B8A8_UNORM,
            .components = {.r = VK_COMPONENT_SWIZZLE_R,
                           .g = VK_COMPONENT_SWIZZLE_G,
                           .b = VK_COMPONENT_SWIZZLE_B,
                           .a = VK_COMPONENT_SWIZZLE_ONE},
            .subresourceRange = {.aspectMask = VK_IMAGE_ASPECT_COLOR_BIT,
                                 .baseMipLevel = 0,
                                 .levelCount = 1,
                                 .baseArrayLayer = 0,
                                 .layerCount = 1}},
        NULL, &r->images[i].color_view_alpha);

    vkCreateFramebuffer(ctx->device,
                        &(VkFramebufferCreateInfo){
                            .sType = VK_STRUCTURE_TYPE_FRAMEBUFFER_CREATE_INFO,
                            .pNext = NULL,
                            .flags = 0,
                            .renderPass = r->render_pass,
                            .attachmentCount = 1,
                            .pAttachments = &r->images[i].color_view,
                            .width = size[0],
                            .height = size[1],
                            .layers = 1},
                        NULL, &r->images[i].framebuffer);
  }
}

void _destroy_image_data(renderer* r, tcontext* ctx) {
  for (int i = 0; i < ctx->fif; i++) {
    vkDestroyFramebuffer(ctx->device, r->images[i].framebuffer, NULL);
    vkDestroyImageView(ctx->device, r->images[i].color_view_alpha, NULL);
    vkDestroyImageView(ctx->device, r->images[i].color_view, NULL);
    vmaDestroyImage(ctx->allocator, r->images[i].color, r->images[i].memory);
  }
}

renderer* renderer_create(tenv* env) {
  tcontext* ctx = env->ctx;
  tuser_data* usr = env->usr;
  renderer* r = calloc(1, sizeof(renderer));
#ifdef VLITHER_ANDROID
  android_startup_stage(8, "Uploading arena textures",
                        "Preparing background, sprite atlas and brand assets");
#endif

  vkCreateSampler(
      ctx->device,
      &(VkSamplerCreateInfo){.sType = VK_STRUCTURE_TYPE_SAMPLER_CREATE_INFO,
                             .pNext = NULL,
                             .flags = 0,
                             .magFilter = VK_FILTER_LINEAR,
                             .minFilter = VK_FILTER_LINEAR,
                             .mipmapMode = VK_SAMPLER_MIPMAP_MODE_LINEAR,
                             .addressModeU = VK_SAMPLER_ADDRESS_MODE_REPEAT,
                             .addressModeV = VK_SAMPLER_ADDRESS_MODE_REPEAT,
                             .addressModeW = VK_SAMPLER_ADDRESS_MODE_REPEAT,
                             .maxLod = VK_LOD_CLAMP_NONE},
      NULL, &r->linear_sampler);

  // The sprite atlas is tightly packed and has no per-cell mip gutters. Keep
  // linear filtering inside the base image but lock sampling to LOD 0 so
  // distant sprites cannot pick up colors from neighboring atlas cells.
  vkCreateSampler(
      ctx->device,
      &(VkSamplerCreateInfo){.sType = VK_STRUCTURE_TYPE_SAMPLER_CREATE_INFO,
                             .pNext = NULL,
                             .flags = 0,
                             .magFilter = VK_FILTER_LINEAR,
                             .minFilter = VK_FILTER_LINEAR,
                             .mipmapMode = VK_SAMPLER_MIPMAP_MODE_NEAREST,
                             .addressModeU = VK_SAMPLER_ADDRESS_MODE_CLAMP_TO_EDGE,
                             .addressModeV = VK_SAMPLER_ADDRESS_MODE_CLAMP_TO_EDGE,
                             .addressModeW = VK_SAMPLER_ADDRESS_MODE_CLAMP_TO_EDGE,
                             .minLod = 0.0f,
                             .maxLod = 0.0f},
      NULL, &r->atlas_sampler);

  vkCreateSampler(ctx->device,
                  &(VkSamplerCreateInfo){
                      .sType = VK_STRUCTURE_TYPE_SAMPLER_CREATE_INFO,
                      .pNext = NULL,
                      .flags = 0,
                      .magFilter = VK_FILTER_NEAREST,
                      .minFilter = VK_FILTER_NEAREST,
                      .mipmapMode = VK_SAMPLER_MIPMAP_MODE_NEAREST,
                      .addressModeU = VK_SAMPLER_ADDRESS_MODE_CLAMP_TO_BORDER,
                      .addressModeV = VK_SAMPLER_ADDRESS_MODE_CLAMP_TO_BORDER,
                      .addressModeW = VK_SAMPLER_ADDRESS_MODE_CLAMP_TO_BORDER,
                      .borderColor = VK_BORDER_COLOR_FLOAT_OPAQUE_BLACK,
                      .maxLod = VK_LOD_CLAMP_NONE},
                  NULL, &r->nearest_sampler);

  /* Whatever the player last chose. Only one is ever resident: swapping is a
     settings action, not a per-frame one, so paying a load for it is cheaper
     than keeping twenty of these in video memory. */
  r->background = background_clamp(env->usr->usrs.arena_background);
  const background_def* bg = &BACKGROUNDS[r->background];
  r->bg_tex = create_mipmap_texture(
      ctx, bg->path ? bg->path : "app/res/textures/background_4k.png");
#ifdef VLITHER_ANDROID
  android_startup_texture("background", r->bg_tex->size[0], r->bg_tex->size[1],
                          1, 4);
#endif
  r->tex_atlas = create_mipmap_texture(ctx, "app/res/textures/tex_atlas_8k.png");
#ifdef VLITHER_ANDROID
  android_startup_texture("atlas", r->tex_atlas->size[0], r->tex_atlas->size[1],
                          2, 4);
#endif
  r->logo_tex =
      create_mipmap_texture(ctx, "app/res/textures/vlither_enhanced_logo.png");
#ifdef VLITHER_ANDROID
  android_startup_texture("logo", r->logo_tex->size[0], r->logo_tex->size[1],
                          3, 4);
#endif
  r->logo_descriptor = igImplVulkan_AddTexture(
      r->atlas_sampler, r->logo_tex->view,
      VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL);
  r->home_icons_tex =
      create_mipmap_texture(ctx, "app/res/textures/home_navigation_icons.png");
#ifdef VLITHER_ANDROID
  android_startup_texture("home-icons", r->home_icons_tex->size[0],
                          r->home_icons_tex->size[1], 4, 4);
#endif
  r->home_icons_descriptor = igImplVulkan_AddTexture(
      r->linear_sampler, r->home_icons_tex->view,
      VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL);

  r->tags_tex = create_mipmap_texture(ctx, "app/res/textures/wyrm_tags.png");
  r->tags_descriptor = igImplVulkan_AddTexture(
      r->linear_sampler, r->tags_tex->view,
      VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL);

  vkCreateRenderPass(
      ctx->device,
      &(VkRenderPassCreateInfo){
          .sType = VK_STRUCTURE_TYPE_RENDER_PASS_CREATE_INFO,
          .pNext = NULL,
          .flags = 0,
          .attachmentCount = 1,
          .pAttachments =
              &(VkAttachmentDescription){
                  .flags = 0,
                  .format = VK_FORMAT_R8G8B8A8_UNORM,
                  .samples = VK_SAMPLE_COUNT_1_BIT,
                  .loadOp = VK_ATTACHMENT_LOAD_OP_CLEAR,
                  .storeOp = VK_ATTACHMENT_STORE_OP_STORE,
                  .stencilLoadOp = VK_ATTACHMENT_LOAD_OP_DONT_CARE,
                  .stencilStoreOp = VK_ATTACHMENT_STORE_OP_DONT_CARE,
                  .initialLayout = VK_IMAGE_LAYOUT_UNDEFINED,
                  .finalLayout = VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL},
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
                          .layout = VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL}},
          .dependencyCount = 0,
          .pDependencies = NULL},
      NULL, &r->render_pass);

  r->images = malloc(sizeof(renderer_image_data) * ctx->fif);
  _create_image_data(r, ctx, ctx->size);
  vec2 quad_data[4] = {{0, 0}, {0, 1}, {1, 0}, {1, 1}};
  r->quad_buffer = tbuffer_create(ctx, quad_data, sizeof(quad_data),
                                  VK_BUFFER_USAGE_VERTEX_BUFFER_BIT);

  vkCreateDescriptorSetLayout(
      ctx->device,
      &(VkDescriptorSetLayoutCreateInfo){
          .sType = VK_STRUCTURE_TYPE_DESCRIPTOR_SET_LAYOUT_CREATE_INFO,
          .pNext = NULL,
          .flags = 0,
          .bindingCount = 4,
          .pBindings =
              (VkDescriptorSetLayoutBinding[]){
                  {.binding = 0,
                   .descriptorType = VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER,
                   .descriptorCount = 1,
                   .stageFlags = VK_SHADER_STAGE_VERTEX_BIT |
                                 VK_SHADER_STAGE_FRAGMENT_BIT},
                  {.binding = 1,
                   .descriptorType = VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER,
                   .descriptorCount = 1,
                   .stageFlags = VK_SHADER_STAGE_FRAGMENT_BIT},
                  {.binding = 2,
                   .descriptorType = VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER,
                   .descriptorCount = 1,
                   .stageFlags = VK_SHADER_STAGE_FRAGMENT_BIT},
                  {.binding = 3,
                   .descriptorType = VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER,
                   .descriptorCount = 1,
                   .stageFlags = VK_SHADER_STAGE_FRAGMENT_BIT}}},
      NULL, &r->global_set_layout);

  vkCreatePipelineLayout(
      ctx->device,
      &(VkPipelineLayoutCreateInfo){
          .sType = VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO,
          .pNext = NULL,
          .flags = 0,
          .setLayoutCount = 1,
          .pSetLayouts = &r->global_set_layout,
          .pushConstantRangeCount = 0,
          .pPushConstantRanges = NULL},
      NULL, &r->pipeline_layout);

  r->mmr = mm_renderer_create(ctx, r->pipeline_layout, r->render_pass);

  r->global_set = malloc(ctx->fif * sizeof(VkDescriptorSet));
  VkDescriptorSetLayout* layouts =
      malloc(ctx->fif * sizeof(VkDescriptorSetLayout));
  for (int i = 0; i < ctx->fif; i++) {
    layouts[i] = r->global_set_layout;
  }

  vkAllocateDescriptorSets(
      ctx->device,
      &(VkDescriptorSetAllocateInfo){
          .sType = VK_STRUCTURE_TYPE_DESCRIPTOR_SET_ALLOCATE_INFO,
          .pNext = NULL,
          .descriptorPool = ctx->descriptor_pool,
          .descriptorSetCount = ctx->fif,
          .pSetLayouts = layouts},
      r->global_set);
  free(layouts);

  r->global.viewport[0] = r->size[0];
  r->global.viewport[1] = r->size[1];
  // Preserve the original arena tiling scale after the mobile PNG is halved.
  r->global.bg_size[0] = BACKGROUNDS[r->background].tile_w;
  r->global.bg_size[1] = BACKGROUNDS[r->background].tile_h;
  r->global.bg_color[0] = 1;
  r->global.bg_color[1] = 1;
  r->global.bg_scale = 1;
  r->global.bg_color[2] = 1;
  r->global.bd_color[0] = 1;
  r->global.bd_color[1] = 1;
  r->global.bd_color[2] = 1;
  r->global.bg_opacity = 0;
  r->global.bd_opacity = 0;
  r->global.view[0] = 0;
  r->global.view[1] = 0;
  r->global.zoom = 1;
  r->global.bd_radius = 1;
  r->global.grd = 1;
  r->global.max_minimap_size = MAX_MINIMAP_SIZE;
  r->global.minimap_data_size = 136;
  r->global.minimap_circ[0] = 0;
  r->global.minimap_circ[1] = 0;
  r->global.minimap_circ[2] = 256;
  r->global.minimap_opacity = 1;
  r->global.lview[0] = -1;
  r->global.lview[1] = -1;

  r->global_buffer = tdbuffer_create(ctx, &r->global, sizeof(r->global),
                                     VK_BUFFER_USAGE_UNIFORM_BUFFER_BIT);

  for (int i = 0; i < ctx->fif; i++)
    vkUpdateDescriptorSets(
        ctx->device, 4,
        (VkWriteDescriptorSet[]){
            {
                .sType = VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET,
                .pNext = NULL,
                .dstSet = r->global_set[i],
                .dstBinding = 0,
                .dstArrayElement = 0,
                .descriptorCount = 1,
                .descriptorType = VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER,
                .pBufferInfo =
                    &(VkDescriptorBufferInfo){r->global_buffer[i].handle, 0,
                                              sizeof(r->global)},
            },
            {
                .sType = VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET,
                .pNext = NULL,
                .dstSet = r->global_set[i],
                .dstBinding = 1,
                .dstArrayElement = 0,
                .descriptorCount = 1,
                .descriptorType = VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER,
                .pImageInfo =
                    &(VkDescriptorImageInfo){
                        r->atlas_sampler, r->tex_atlas->view,
                        VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL},
            },
            {
                .sType = VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET,
                .pNext = NULL,
                .dstSet = r->global_set[i],
                .dstBinding = 2,
                .dstArrayElement = 0,
                .descriptorCount = 1,
                .descriptorType = VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER,
                .pImageInfo =
                    &(VkDescriptorImageInfo){
                        r->linear_sampler, r->bg_tex->view,
                        VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL},
            },
            {
                .sType = VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET,
                .pNext = NULL,
                .dstSet = r->global_set[i],
                .dstBinding = 3,
                .dstArrayElement = 0,
                .descriptorCount = 1,
                .descriptorType = VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER,
                .pImageInfo =
                    &(VkDescriptorImageInfo){
                        r->nearest_sampler, r->mmr->minimap_tex[i]->view,
                        VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL},
            }},
        0, NULL);

  r->bgr = bg_renderer_create(ctx, r->pipeline_layout, r->render_pass);
  r->bstb = bst_renderer_create(ctx, MAX_BOOST_INSTANCES, r->pipeline_layout, r->render_pass);
  r->bpr = bp_renderer_create(ctx, MAX_SPRITE_INSTANCES, r->pipeline_layout, r->render_pass);
  r->bsta = bst_renderer_create(ctx, MAX_BOOST_INSTANCES, r->pipeline_layout, r->render_pass);
  r->fdr = fd_renderer_create(ctx, MAX_FOOD_INSTANCES, MAX_PREYS, r->pipeline_layout, r->render_pass);
  r->bdr = bd_renderer_create(ctx, r->pipeline_layout, r->render_pass);
  r->astr = bp_renderer_create(ctx, 2, r->pipeline_layout, r->render_pass);
  r->cr = spr_renderer_create(ctx, 1, r->pipeline_layout, env->ctx->renderpass);

#ifdef VLITHER_ANDROID
  android_startup_stage(9, "Graphics pipelines assembled",
                        "Arena, sprites, food, minimap and UI pipelines are ready");
#endif

  return r;
}

void renderer_render(renderer* r, tcontext* ctx, vec4 clear_color) {
  tcontext_frame* fr = ctx->frames + ctx->current_frame;

  r->global.viewport[0] = r->size[0];
  r->global.viewport[1] = r->size[1];
  memcpy(r->global_buffer[ctx->current_frame].data, &r->global,
         sizeof(r->global));

  mm_renderer_prerender(r->mmr, ctx);

  vkCmdBeginRenderPass(
      fr->cmd,
      &(VkRenderPassBeginInfo){
          .sType = VK_STRUCTURE_TYPE_RENDER_PASS_BEGIN_INFO,
          .pNext = NULL,
          .renderPass = r->render_pass,
          .framebuffer = r->images[ctx->current_frame].framebuffer,
          .renderArea = {.offset = {0, 0}, .extent = {r->size[0], r->size[1]}},
          .clearValueCount = 1,
          .pClearValues =
              &(VkClearValue){
                  .color = {.float32 = {clear_color[0], clear_color[1],
                                        clear_color[2], clear_color[3]}}}},
      VK_SUBPASS_CONTENTS_INLINE);
  vkCmdBindVertexBuffers(fr->cmd, 0, 1, &r->quad_buffer->handle,
                         (VkDeviceSize[]){0});

  vkCmdSetViewport(fr->cmd, 0, 1, &(VkViewport){0, 0, r->size[0], r->size[1]});
  vkCmdSetScissor(fr->cmd, 0, 1, &(VkRect2D){{0, 0}, {r->size[0], r->size[1]}});
  vkCmdBindDescriptorSets(fr->cmd, VK_PIPELINE_BIND_POINT_GRAPHICS,
                          r->pipeline_layout, 0, 1,
                          &r->global_set[ctx->current_frame], 0, NULL);
  bg_renderer_render(r->bgr, ctx);
  fd_renderer_render(r->fdr, ctx);
  bst_renderer_render(r->bstb, ctx);
  bp_renderer_render(r->bpr, ctx);
  bst_renderer_render(r->bsta, ctx);
  bd_renderer_render(r->bdr, ctx);
  bp_renderer_render(r->astr, ctx);
  mm_renderer_render(r->mmr, ctx);
  vkCmdEndRenderPass(ctx->frames[ctx->current_frame].cmd);
}

void renderer_render_cursor(renderer* r, tcontext* ctx) {
  tcontext_frame* fr = ctx->frames + ctx->current_frame;
  vkCmdBindVertexBuffers(fr->cmd, 0, 1, &r->quad_buffer->handle,
                         (VkDeviceSize[]){0});

  vkCmdSetViewport(fr->cmd, 0, 1, &(VkViewport){0, 0, r->size[0], r->size[1]});
  vkCmdSetScissor(fr->cmd, 0, 1, &(VkRect2D){{0, 0}, {r->size[0], r->size[1]}});
  vkCmdBindDescriptorSets(fr->cmd, VK_PIPELINE_BIND_POINT_GRAPHICS,
                          r->pipeline_layout, 0, 1,
                          &r->global_set[ctx->current_frame], 0, NULL);

  spr_renderer_render(r->cr, ctx);
}

/**
 * Swaps the arena floor. See renderer.h.
 *
 * "None" keeps a texture bound rather than unbinding one — a descriptor that
 * points at nothing is undefined behaviour in the shader, and the pass is
 * skipped by opacity elsewhere. What it must not do is keep the previous
 * background's tile size, or a later selection would inherit it.
 */
void renderer_set_background(renderer* r, tcontext* ctx, int index) {
  index = background_clamp(index);
  if (index == r->background) return;
  const background_def* bg = &BACKGROUNDS[index];
  const char* path = bg->path ? bg->path : BACKGROUNDS[BACKGROUND_WYRM].path;

  texture* next = create_mipmap_texture(ctx, path);
  if (!next) return; /* keep what is on screen rather than showing nothing */

  /* Frames already recorded may still read the old image. */
  vkDeviceWaitIdle(ctx->device);
  destroy_texture(ctx, r->bg_tex);
  r->bg_tex = next;
  r->background = index;
  r->global.bg_size[0] = bg->tile_w;
  r->global.bg_size[1] = bg->tile_h;

  for (int i = 0; i < ctx->fif; i++)
    vkUpdateDescriptorSets(
        ctx->device, 1,
        (VkWriteDescriptorSet[]){
            {
                .sType = VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET,
                .pNext = NULL,
                .dstSet = r->global_set[i],
                .dstBinding = 2,
                .dstArrayElement = 0,
                .descriptorCount = 1,
                .descriptorType = VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER,
                .pImageInfo =
                    &(VkDescriptorImageInfo){
                        r->linear_sampler, r->bg_tex->view,
                        VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL},
            },
        },
        0, NULL);
}

void renderer_destroy(renderer* r, tcontext* ctx) {
  spr_renderer_destroy(r->cr, ctx);
  bd_renderer_destroy(r->bdr, ctx);
  bp_renderer_destroy(r->astr, ctx);
  bst_renderer_destroy(r->bsta, ctx);
  bp_renderer_destroy(r->bpr, ctx);
  bst_renderer_destroy(r->bstb, ctx);
  fd_renderer_destroy(r->fdr, ctx);
  bg_renderer_destroy(r->bgr, ctx);
  tdbuffer_destroy(ctx, r->global_buffer);
  free(r->global_set);
  mm_renderer_destroy(r->mmr, ctx);
  vkDestroyPipelineLayout(ctx->device, r->pipeline_layout, NULL);
  vkDestroyDescriptorSetLayout(ctx->device, r->global_set_layout, NULL);
  tbuffer_destroy(ctx, r->quad_buffer);
  _destroy_image_data(r, ctx);
  vkDestroyRenderPass(ctx->device, r->render_pass, NULL);
  free(r->images);
  if (r->logo_descriptor)
    igImplVulkan_RemoveTexture(r->logo_descriptor);
  if (r->home_icons_descriptor)
    igImplVulkan_RemoveTexture(r->home_icons_descriptor);
  if (r->tags_descriptor) igImplVulkan_RemoveTexture(r->tags_descriptor);
  destroy_texture(ctx, r->tags_tex);
  destroy_texture(ctx, r->home_icons_tex);
  destroy_texture(ctx, r->logo_tex);
  destroy_texture(ctx, r->tex_atlas);
  destroy_texture(ctx, r->bg_tex);
  vkDestroySampler(ctx->device, r->nearest_sampler, NULL);
  vkDestroySampler(ctx->device, r->atlas_sampler, NULL);
  vkDestroySampler(ctx->device, r->linear_sampler, NULL);
  free(r);
}

void renderer_resize(renderer* r, tcontext* ctx, ivec2 size) {
  vkQueueWaitIdle(ctx->queue);
  _destroy_image_data(r, ctx);
  _create_image_data(r, ctx, size);
}

void renderer_clear_instances(renderer* r) {
  r->fdr->num_instances = 0;
  r->fdr->num_p_instances = 0;
  r->bsta->num_instances = 0;
  r->bpr->num_instances = 0;
  r->bstb->num_instances = 0;
  r->astr->num_instances = 0;
  r->cr->num_instances = 0;
}
