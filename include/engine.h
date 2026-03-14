#ifndef ITE_ENGINE_H
#define ITE_ENGINE_H

#include <stddef.h>
#include <stdint.h>

struct ite_Engine;

typedef enum ite_EngineStatus {
  ite_EngineStatus_ok = 0,
  ite_EngineStatus_invalid_arg = 1,
  ite_EngineStatus_not_initialized = 2,
  ite_EngineStatus_io_error = 3,
  ite_EngineStatus_gpu_error = 4,
  ite_EngineStatus_capacity_exceeded = 5,
} ite_EngineStatus;

typedef struct ite_CameraUniform {
  float transform[6];
  uint32_t viewport_width_px;
  uint32_t viewport_height_px;
} ite_CameraUniform;

typedef struct ite_Rect {
  float x;
  float y;
  float w;
  float h;
  uint32_t color_rgba8;
  uint32_t _pad0;
  uint32_t _pad1;
  uint32_t _pad2;
} ite_Rect;

typedef struct ite_EngineConfig {
  uint32_t abi_version;
  uint32_t max_rects;
  uint32_t max_visible_rects;
  uint32_t initial_width_px;
  uint32_t initial_height_px;
  float min_zoom;
  float max_zoom;
} ite_EngineConfig;

typedef struct ite_FrameStats {
  uint32_t total_rects;
  uint32_t visible_rects;
  uint32_t width_px;
  uint32_t height_px;
} ite_FrameStats;

uint32_t ite_engine_header_version(void);
ite_EngineStatus ite_engine_create(struct ite_Engine **out_engine, const ite_EngineConfig *config);
void ite_engine_destroy(struct ite_Engine *engine);
ite_EngineStatus ite_engine_init(struct ite_Engine *engine, void *metal_device, void *command_queue, void *shader_library);
ite_EngineStatus ite_engine_init_with_metallib_path(struct ite_Engine *engine, void *metal_device, void *command_queue, const char *metallib_path);
ite_EngineStatus ite_engine_replace_rects(struct ite_Engine *engine, const ite_Rect *rects, size_t rect_count);
ite_EngineStatus ite_engine_resize(struct ite_Engine *engine, uint32_t width_px, uint32_t height_px);
ite_EngineStatus ite_engine_pan(struct ite_Engine *engine, float delta_x_px, float delta_y_px);
ite_EngineStatus ite_engine_zoom(struct ite_Engine *engine, float delta, float anchor_x_px, float anchor_y_px);
ite_EngineStatus ite_engine_render(struct ite_Engine *engine, void *drawable_texture);
ite_EngineStatus ite_engine_render_drawable(struct ite_Engine *engine, void *drawable);
ite_EngineStatus ite_engine_get_stats(const struct ite_Engine *engine, ite_FrameStats *out_stats);
const char *ite_engine_get_last_error(const struct ite_Engine *engine);

#endif
