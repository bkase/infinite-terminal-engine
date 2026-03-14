#include "engine.h"

int main(void) {
    struct ite_Engine *engine = 0;
    struct ite_EngineConfig config = {
        .abi_version = ite_engine_header_version(),
        .max_scene_rects = 16,
        .max_visible_rects = 16,
        ._reserved0 = 0,
    };

    if (ite_engine_create(&engine, &config) != ite_EngineStatus_ok) {
        return 1;
    }

    ite_engine_destroy(engine);
    return 0;
}
