#ifndef ITE_ENGINE_H
#define ITE_ENGINE_H

#include <stddef.h>
#include <stdint.h>

struct Engine;

typedef enum EngineStatus {
  EngineStatus_ok = 0,
  EngineStatus_invalid_arg = 1,
  EngineStatus_not_initialized = 2,
  EngineStatus_io_error = 3,
  EngineStatus_gpu_error = 4,
  EngineStatus_capacity_exceeded = 5,
} EngineStatus;

typedef struct CameraUniform {
  float transform[6];
  uint32_t viewport_width_px;
  uint32_t viewport_height_px;
} CameraUniform;

typedef struct Rect {
  float x;
  float y;
  float w;
  float h;
  uint32_t color_rgba8;
  uint32_t _pad0;
  uint32_t _pad1;
  uint32_t _pad2;
} Rect;

typedef struct EngineConfig {
  uint32_t abi_version;
  uint32_t max_rects;
  uint32_t max_visible_rects;
  uint32_t initial_width_px;
  uint32_t initial_height_px;
  float min_zoom;
  float max_zoom;
} EngineConfig;

typedef struct FrameStats {
  uint32_t total_rects;
  uint32_t visible_rects;
  uint32_t width_px;
  uint32_t height_px;
} FrameStats;

uint32_t ite_engine_header_version(void);
EngineStatus ite_engine_create(struct Engine **out_engine, const EngineConfig *config);
void ite_engine_destroy(struct Engine *engine);
EngineStatus ite_engine_init(struct Engine *engine, void *metal_device, void *command_queue, void *shader_library);
EngineStatus ite_engine_replace_rects(struct Engine *engine, const Rect *rects, size_t rect_count);
EngineStatus ite_engine_resize(struct Engine *engine, uint32_t width_px, uint32_t height_px);
EngineStatus ite_engine_pan(struct Engine *engine, float delta_x_px, float delta_y_px);
EngineStatus ite_engine_zoom(struct Engine *engine, float delta, float anchor_x_px, float anchor_y_px);
EngineStatus ite_engine_render(struct Engine *engine, void *drawable_texture);
EngineStatus ite_engine_get_stats(const struct Engine *engine, FrameStats *out_stats);
const char *ite_engine_get_last_error(const struct Engine *engine);

#endif
