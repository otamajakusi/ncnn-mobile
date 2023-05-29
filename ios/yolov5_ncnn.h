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
  uint32_t label;
  float prob;
  bool last;
} Yolov5NcnnObject;

typedef struct {
  float x;
  float y;
  float w;
  float h;
  uint64_t trackId;
  uint64_t frameId;
  float score;
  bool last;
} Yolov5NcnnSTrack;

bool yolov5NcnnInit(const char* param, const char* bin);
const Yolov5NcnnObject* yolov5NcnnDetect(const uint8_t* pixel, uint32_t width,
                                         uint32_t height, bool use_gpu);

const Yolov5NcnnSTrack* yolov5NcnnDetectSTrack(const Yolov5NcnnObject* objects);

const char* yolov5NcnnClassName(uint32_t index);

#if defined(__cplusplus)
}
#endif  // defined(__cplusplus)
