#pragma once

#include <stdbool.h>

#ifdef __OBJC__
@class CAMetalLayer;
#else
typedef void CAMetalLayer;
#endif

#ifdef __cplusplus
extern "C" {
#endif

bool WyrmEngineBootstrap(CAMetalLayer *metal_layer);
const char *WyrmEngineStatus(void);

#ifdef __cplusplus
}
#endif

