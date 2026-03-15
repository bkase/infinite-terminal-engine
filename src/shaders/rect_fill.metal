#include <metal_stdlib>
using namespace metal;

// Keep this layout in lockstep with src/shared/abi.zig.
struct CameraUniform {
    float transform[6];
    uint viewport_width_px;
    uint viewport_height_px;
};

struct Rect {
    float x;
    float y;
    float w;
    float h;
    uint color_rgba8;
    uint _pad0;
    uint _pad1;
    uint _pad2;
};

struct VertexOut {
    float4 position [[position]];
    float4 color;
};

struct TexturedQuad {
    float x;
    float y;
    float w;
    float h;
    float u0;
    float v0;
    float u1;
    float v1;
};

struct TexturedVertexOut {
    float4 position [[position]];
    float2 uv;
};

vertex VertexOut rect_vertex(
    uint vertex_id [[vertex_id]],
    uint instance_id [[instance_id]],
    constant CameraUniform& camera [[buffer(0)]],
    constant Rect* rects [[buffer(1)]]
) {
    // Two triangles forming a unit quad, expanded per rectangle instance.
    constexpr float2 quad[6] = {
        float2(0.0, 0.0),
        float2(1.0, 0.0),
        float2(0.0, 1.0),
        float2(1.0, 0.0),
        float2(1.0, 1.0),
        float2(0.0, 1.0),
    };

    Rect rect = rects[instance_id];
    float2 unit = quad[vertex_id];
    float2 canvas = float2(rect.x, rect.y) + unit * float2(rect.w, rect.h);
    float x = camera.transform[0] * canvas.x + camera.transform[2] * canvas.y + camera.transform[4];
    float y = camera.transform[1] * canvas.x + camera.transform[3] * canvas.y + camera.transform[5];
    float ndc_x = (x / float(camera.viewport_width_px)) * 2.0 - 1.0;
    float ndc_y = 1.0 - (y / float(camera.viewport_height_px)) * 2.0;

    float4 color = float4(
        float((rect.color_rgba8 >> 24) & 0xff) / 255.0,
        float((rect.color_rgba8 >> 16) & 0xff) / 255.0,
        float((rect.color_rgba8 >> 8) & 0xff) / 255.0,
        float(rect.color_rgba8 & 0xff) / 255.0
    );

    VertexOut out;
    out.position = float4(ndc_x, ndc_y, 0.0, 1.0);
    out.color = color;
    return out;
}

fragment float4 rect_fragment(VertexOut in [[stage_in]]) {
    return in.color;
}

vertex TexturedVertexOut textured_quad_vertex(
    uint vertex_id [[vertex_id]],
    constant CameraUniform& camera [[buffer(0)]],
    constant TexturedQuad& quad [[buffer(1)]]
) {
    constexpr float2 unit_quad[6] = {
        float2(0.0, 0.0),
        float2(1.0, 0.0),
        float2(0.0, 1.0),
        float2(1.0, 0.0),
        float2(1.0, 1.0),
        float2(0.0, 1.0),
    };

    float2 unit = unit_quad[vertex_id];
    float2 canvas = float2(quad.x, quad.y) + unit * float2(quad.w, quad.h);
    float x = camera.transform[0] * canvas.x + camera.transform[2] * canvas.y + camera.transform[4];
    float y = camera.transform[1] * canvas.x + camera.transform[3] * canvas.y + camera.transform[5];
    float ndc_x = (x / float(camera.viewport_width_px)) * 2.0 - 1.0;
    float ndc_y = 1.0 - (y / float(camera.viewport_height_px)) * 2.0;

    TexturedVertexOut out;
    out.position = float4(ndc_x, ndc_y, 0.0, 1.0);
    out.uv = mix(float2(quad.u0, quad.v0), float2(quad.u1, quad.v1), unit);
    return out;
}

fragment float4 textured_quad_fragment(
    TexturedVertexOut in [[stage_in]],
    texture2d<float> terminal_texture [[texture(0)]]
) {
    constexpr sampler texture_sampler(mag_filter::nearest, min_filter::linear);
    return terminal_texture.sample(texture_sampler, in.uv);
}
