#ifndef ANDROID_STARTUP_H
#define ANDROID_STARTUP_H

void android_startup_stage(int stage, const char* title, const char* detail);
void android_startup_failure(int stage, const char* title, const char* detail);
void android_startup_gpu(const char* name, const char* vulkan_version,
                         int max_texture_dimension);
void android_startup_texture(const char* label, int width, int height,
                             int completed, int total);
void android_startup_ready(void);

#endif

