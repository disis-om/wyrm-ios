#include "WyrmOriginalAdapter.h"
#include <stdlib.h>
#include <string.h>

VkResult WyrmIOSCreateInstance(const VkInstanceCreateInfo* input,
                              const VkAllocationCallbacks* allocator, VkInstance* output) {
  uint32_t count = 0;
  VkResult result = vkEnumerateInstanceExtensionProperties(NULL, &count, NULL);
  if (result != VK_SUCCESS) return result;
  VkExtensionProperties* available = calloc(count ? count : 1, sizeof(*available));
  if (!available) return VK_ERROR_OUT_OF_HOST_MEMORY;
  result = vkEnumerateInstanceExtensionProperties(NULL, &count, available);
  bool portability = false;
  for (uint32_t i = 0; result == VK_SUCCESS && i < count; ++i)
    if (!strcmp(available[i].extensionName, "VK_KHR_portability_enumeration")) portability = true;
  free(available);
  if (result != VK_SUCCESS) return result;
  VkInstanceCreateInfo info = *input;
  const char** extensions = calloc(input->enabledExtensionCount + 1, sizeof(*extensions));
  if (!extensions) return VK_ERROR_OUT_OF_HOST_MEMORY;
  for (uint32_t i = 0; i < input->enabledExtensionCount; ++i) extensions[i] = input->ppEnabledExtensionNames[i];
  if (portability) {
    extensions[info.enabledExtensionCount++] = "VK_KHR_portability_enumeration";
    info.flags |= 0x00000001; /* VK_INSTANCE_CREATE_ENUMERATE_PORTABILITY_BIT_KHR */
  }
  info.ppEnabledExtensionNames = extensions;
  result = vkCreateInstance(&info, allocator, output);
  free(extensions);
  return result;
}

VkResult WyrmIOSCreateDevice(VkPhysicalDevice gpu, const VkDeviceCreateInfo* input,
                            const VkAllocationCallbacks* allocator, VkDevice* output) {
  uint32_t count = 0;
  VkResult result = vkEnumerateDeviceExtensionProperties(gpu, NULL, &count, NULL);
  if (result != VK_SUCCESS) return result;
  VkExtensionProperties* available = calloc(count ? count : 1, sizeof(*available));
  if (!available) return VK_ERROR_OUT_OF_HOST_MEMORY;
  result = vkEnumerateDeviceExtensionProperties(gpu, NULL, &count, available);
  bool portability = false;
  for (uint32_t i = 0; result == VK_SUCCESS && i < count; ++i)
    if (!strcmp(available[i].extensionName, "VK_KHR_portability_subset")) portability = true;
  free(available);
  if (result != VK_SUCCESS) return result;
  VkDeviceCreateInfo info = *input;
  const char** extensions = calloc(input->enabledExtensionCount + 1, sizeof(*extensions));
  if (!extensions) return VK_ERROR_OUT_OF_HOST_MEMORY;
  for (uint32_t i = 0; i < input->enabledExtensionCount; ++i) extensions[i] = input->ppEnabledExtensionNames[i];
  if (portability) extensions[info.enabledExtensionCount++] = "VK_KHR_portability_subset";
  info.ppEnabledExtensionNames = extensions;
  result = vkCreateDevice(gpu, &info, allocator, output);
  free(extensions);
  return result;
}
