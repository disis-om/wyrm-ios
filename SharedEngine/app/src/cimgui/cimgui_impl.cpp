#include "./imgui/imgui.h"
#ifdef IMGUI_ENABLE_FREETYPE
#include "./imgui/misc/freetype/imgui_freetype.h"
#endif
#include "./imgui/imgui_internal.h"
#include "cimgui.h"

#ifdef VLITHER_ANDROID
#include "imgui/imgui_impl_sdl3.h"
#include <SDL3/SDL.h>
#else
#include "imgui/imgui_impl_glfw.h"
#endif
#include "imgui/imgui_impl_vulkan.h"

#include "cimgui_impl.h"

#ifndef VLITHER_ANDROID
CIMGUI_API bool igImplGlfw_InitForVulkan(GLFWwindow* window,bool install_callbacks)
{
	return ImGui_ImplGlfw_InitForVulkan(window, install_callbacks);
}
CIMGUI_API void igImplGlfw_Shutdown(void)
{
	ImGui_ImplGlfw_Shutdown();
}
CIMGUI_API void igImplGlfw_NewFrame(void)
{
	ImGui_ImplGlfw_NewFrame();
}
#else
CIMGUI_API bool igImplSDL3_InitForVulkan(void* window)
{
	return ImGui_ImplSDL3_InitForVulkan((SDL_Window*)window);
}
CIMGUI_API void igImplSDL3_Shutdown(void)
{
	ImGui_ImplSDL3_Shutdown();
}
CIMGUI_API void igImplSDL3_NewFrame(void)
{
	ImGui_ImplSDL3_NewFrame();
}
CIMGUI_API bool igImplSDL3_ProcessEvent(const void* event)
{
	return ImGui_ImplSDL3_ProcessEvent((const SDL_Event*)event);
}
#endif

CIMGUI_API bool igImplVulkan_Init(ImGui_ImplVulkan_InitInfo* info)
{
	return ImGui_ImplVulkan_Init(info);
}
CIMGUI_API void igImplVulkan_Shutdown(void)
{
	ImGui_ImplVulkan_Shutdown();
}
CIMGUI_API void igImplVulkan_NewFrame(void)
{
	ImGui_ImplVulkan_NewFrame();
}
CIMGUI_API void igImplVulkan_RenderDrawData(ImDrawData* draw_data,VkCommandBuffer command_buffer,VkPipeline pipeline)
{
	ImGui_ImplVulkan_RenderDrawData(draw_data, command_buffer, pipeline);
}
CIMGUI_API void igImplVulkan_UpdateTexture(ImTextureData* tex)
{
	ImGui_ImplVulkan_UpdateTexture(tex);
}
CIMGUI_API VkDescriptorSet igImplVulkan_AddTexture(VkSampler sampler,VkImageView image_view,VkImageLayout image_layout)
{
	return ImGui_ImplVulkan_AddTexture(sampler, image_view, image_layout);
}
CIMGUI_API void igImplVulkan_RemoveTexture(VkDescriptorSet descriptor_set)
{
	ImGui_ImplVulkan_RemoveTexture(descriptor_set);
}

CIMGUI_API ImGui_ImplVulkanH_Window* ImGui_ImplVulkanH_Window_ImGui_ImplVulkanH_Window()
{
	return IM_NEW(ImGui_ImplVulkanH_Window)();
}
CIMGUI_API void ImGui_ImplVulkanH_Window_Construct(ImGui_ImplVulkanH_Window* self)
{
	IM_PLACEMENT_NEW(self) ImGui_ImplVulkanH_Window();
}
