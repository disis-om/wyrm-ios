#pragma once

#include <stdbool.h>
#include "WyrmOfflineSlice.h"

#ifdef __OBJC__
@class CAMetalLayer;
#else
typedef void CAMetalLayer;
#endif

#ifdef __cplusplus
extern "C" {
#endif

bool WyrmEngineBootstrap(CAMetalLayer *metal_layer);
bool WyrmEngineFrame(void);
const char *WyrmEngineStatus(void);
void WyrmEngineShutdown(void);

#ifdef __cplusplus
}
#endif
