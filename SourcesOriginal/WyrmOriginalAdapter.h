#pragma once
#include <stdbool.h>
#include <vulkan/vulkan.h>
typedef struct tenv tenv;
void WyrmIOSDrawShell(tenv* env);
void WyrmIOSRequestPlay(const char* name, const char* address, bool offline);
void WyrmIOSRequestLandscape(void);
VkResult WyrmIOSCreateInstance(const VkInstanceCreateInfo*, const VkAllocationCallbacks*, VkInstance*);
VkResult WyrmIOSCreateDevice(VkPhysicalDevice, const VkDeviceCreateInfo*, const VkAllocationCallbacks*, VkDevice*);
