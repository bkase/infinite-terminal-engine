#ifndef ITE_ENGINE_H
#define ITE_ENGINE_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#define ITE_ENGINE_ABI_VERSION 1u

typedef struct ite_Engine ite_Engine;

typedef struct ite_CameraUniform {
  float transform[6];
  uint32_t viewport_width_px;
  uint32_t viewport_height_px;
} ite_CameraUniform;

typedef struct ite_Rect {
  float x;
  float y;
  float width;
  float height;
  uint32_t color_rgba8;
  uint32_t _pad0;
  uint32_t _pad1;
  uint32_t _pad2;
} ite_Rect;

typedef enum ite_EngineStatus {
  ite_EngineStatus_ok = 0,
  ite_EngineStatus_invalid_argument = 1,
  ite_EngineStatus_out_of_memory = 2,
  ite_EngineStatus_failed_precondition = 3,
  ite_EngineStatus_visible_set_capacity_exceeded = 4,
} ite_EngineStatus;

typedef struct ite_EngineConfig {
  uint32_t abi_version;
  uint32_t max_scene_rects;
  uint32_t max_visible_rects;
  uint32_t _reserved0;
} ite_EngineConfig;

typedef struct ite_EngineStats {
  uint32_t scene_rect_count;
  uint32_t visible_rect_count;
  uint32_t draw_rect_count;
  ite_EngineStatus last_status;
} ite_EngineStats;

uint32_t ite_engine_header_version(void);
ite_EngineStatus ite_engine_create(ite_Engine **out_engine, const ite_EngineConfig *config);
void ite_engine_destroy(ite_Engine *engine);
ite_EngineStatus ite_engine_init(
    ite_Engine *engine,
    void *metal_device,
    void *command_queue,
    void *shader_library);
ite_EngineStatus ite_engine_render(
    ite_Engine *engine,
    const ite_CameraUniform *camera,
    const ite_Rect *rects,
    uint32_t rect_count,
    void *drawable_texture);
ite_EngineStatus ite_engine_get_stats(const ite_Engine *engine, ite_EngineStats *out_stats);
const char *ite_engine_get_last_error(const ite_Engine *engine);

#ifdef __cplusplus
}
#endif

#endif
