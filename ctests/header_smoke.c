#include "engine.h"

int main(void) {
    struct Engine *engine = 0;
    struct EngineConfig config = {
        .abi_version = ite_engine_header_version(),
        .max_rects = 16,
        .max_visible_rects = 16,
        .initial_width_px = 640,
        .initial_height_px = 480,
        .min_zoom = 0.125f,
        .max_zoom = 8.0f,
    };

    if (ite_engine_create(&engine, &config) != EngineStatus_ok) {
        return 1;
    }
    ite_engine_destroy(engine);
    return 0;
}
