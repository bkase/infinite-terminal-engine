#ifndef ITE_METAL_BRIDGE_H
#define ITE_METAL_BRIDGE_H

#include <stddef.h>
#include <stdint.h>

#include "../../include/engine.h"

void *ite_metal_create_system_device(void);
void *ite_metal_create_command_queue(void *device);
void *ite_metal_load_library_from_path(void *device, const char *metallib_path, char *error_buf, size_t error_buf_len);
void *ite_metal_create_offscreen_texture(void *device, uint32_t width, uint32_t height, char *error_buf, size_t error_buf_len);
void ite_metal_release_handle(void *handle);
void ite_metal_destroy_renderer(void *renderer);

void *ite_metal_create_renderer(void *device, void *command_queue, void *library, char *error_buf, size_t error_buf_len);
int ite_metal_renderer_draw(
    void *renderer,
    void *texture,
    const ite_CameraUniform *camera,
    const ite_Rect *rects,
    uint32_t rect_count,
    char *error_buf,
    size_t error_buf_len
);
int ite_metal_texture_read_rgba8(
    void *texture,
    uint8_t *out_pixels,
    size_t out_pixels_len,
    char *error_buf,
    size_t error_buf_len
);

#endif
