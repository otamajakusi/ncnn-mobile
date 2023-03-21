#pragma once

#include <stdbool.h>
#include <stdint.h>

#if defined(__cplusplus)
extern "C" {
#endif  // defined(__cplusplus)

typedef struct {
  float x;
  float y;
  float w;
  float h;
  int label;
  float prob;
  bool last;
} Object;

bool yolov5NcnnInit(const char* param, const char* bin);
Object* yolov5NcnnDetect(const uint8_t* pixel, uint32_t width, uint32_t height,
                         bool use_gpu);

#if defined(__cplusplus)
}
#endif  // defined(__cplusplus)
