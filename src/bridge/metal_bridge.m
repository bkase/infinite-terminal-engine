#import "metal_bridge.h"

#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#import <QuartzCore/CAMetalLayer.h>

typedef struct IteMetalRenderer {
    id<MTLDevice> device;
    id<MTLCommandQueue> command_queue;
    id<MTLLibrary> library;
    id<MTLRenderPipelineState> pipeline;
} IteMetalRenderer;

static void ite_write_error(char *buffer, size_t len, NSString *message) {
    if (buffer == NULL || len == 0) {
        return;
    }

    NSData *data = [message dataUsingEncoding:NSUTF8StringEncoding];
    size_t copy_len = MIN(len - 1, data.length);
    memcpy(buffer, data.bytes, copy_len);
    buffer[copy_len] = '\0';
}

void *ite_metal_create_system_device(void) {
    return [MTLCreateSystemDefaultDevice() retain];
}

void *ite_metal_create_command_queue(void *device_handle) {
    id<MTLDevice> device = (__bridge id<MTLDevice>)device_handle;
    if (device == nil) {
        return NULL;
    }
    return [device newCommandQueue];
}

void *ite_metal_load_library_from_path(void *device_handle, const char *metallib_path, char *error_buf, size_t error_buf_len) {
    id<MTLDevice> device = (__bridge id<MTLDevice>)device_handle;
    if (device == nil || metallib_path == NULL) {
        ite_write_error(error_buf, error_buf_len, @"missing Metal device or metallib path");
        return NULL;
    }

    NSError *error = nil;
    NSURL *url = [NSURL fileURLWithPath:[NSString stringWithUTF8String:metallib_path]];
    id<MTLLibrary> library = [device newLibraryWithURL:url error:&error];
    if (library == nil) {
        ite_write_error(error_buf, error_buf_len, error.localizedDescription ?: @"unable to load metallib");
        return NULL;
    }

    return library;
}

void *ite_metal_create_offscreen_texture(void *device_handle, uint32_t width, uint32_t height, char *error_buf, size_t error_buf_len) {
    id<MTLDevice> device = (__bridge id<MTLDevice>)device_handle;
    if (device == nil) {
        ite_write_error(error_buf, error_buf_len, @"missing Metal device");
        return NULL;
    }

    MTLTextureDescriptor *descriptor = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA8Unorm
                                                                                           width:width
                                                                                          height:height
                                                                                       mipmapped:NO];
    descriptor.usage = MTLTextureUsageRenderTarget | MTLTextureUsageShaderRead;
    descriptor.storageMode = MTLStorageModeShared;
    id<MTLTexture> texture = [device newTextureWithDescriptor:descriptor];
    if (texture == nil) {
        ite_write_error(error_buf, error_buf_len, @"unable to create offscreen texture");
        return NULL;
    }
    return texture;
}

void ite_metal_release_handle(void *handle) {
    if (handle != NULL) {
        [(id)handle release];
    }
}

void ite_metal_destroy_renderer(void *renderer_handle) {
    if (renderer_handle != NULL) {
        IteMetalRenderer *renderer = (IteMetalRenderer *)renderer_handle;
        [renderer->device release];
        [renderer->command_queue release];
        [renderer->library release];
        [renderer->pipeline release];
        renderer->device = nil;
        renderer->command_queue = nil;
        renderer->library = nil;
        renderer->pipeline = nil;
        free(renderer);
    }
}

static id<MTLCommandBuffer> ite_metal_create_command_buffer(id<MTLCommandQueue> command_queue, char *error_buf, size_t error_buf_len) {
    id<MTLCommandBuffer> command_buffer = [command_queue commandBuffer];
    if (command_buffer == nil) {
        ite_write_error(error_buf, error_buf_len, @"unable to create command buffer");
    }
    return command_buffer;
}

static int ite_metal_finalize_command_buffer(
    id<MTLCommandBuffer> command_buffer,
    id<MTLDrawable> drawable,
    char *error_buf,
    size_t error_buf_len
) {
    if (drawable != nil) {
        [command_buffer presentDrawable:drawable];
    }

    [command_buffer commit];
    [command_buffer waitUntilCompleted];
    if (command_buffer.error != nil) {
        ite_write_error(error_buf, error_buf_len, command_buffer.error.localizedDescription ?: @"command buffer failed");
        return 0;
    }

    return 1;
}

void *ite_metal_create_renderer(void *device_handle, void *command_queue_handle, void *library_handle, char *error_buf, size_t error_buf_len) {
    id<MTLDevice> device = (__bridge id<MTLDevice>)device_handle;
    id<MTLCommandQueue> command_queue = (__bridge id<MTLCommandQueue>)command_queue_handle;
    id<MTLLibrary> library = (__bridge id<MTLLibrary>)library_handle;
    if (device == nil || command_queue == nil || library == nil) {
        ite_write_error(error_buf, error_buf_len, @"missing renderer dependency");
        return NULL;
    }

    id<MTLFunction> vertex = [library newFunctionWithName:@"rect_vertex"];
    id<MTLFunction> fragment = [library newFunctionWithName:@"rect_fragment"];
    if (vertex == nil || fragment == nil) {
        ite_write_error(error_buf, error_buf_len, @"missing shader entrypoints");
        return NULL;
    }

    MTLRenderPipelineDescriptor *descriptor = [[MTLRenderPipelineDescriptor alloc] init];
    descriptor.vertexFunction = vertex;
    descriptor.fragmentFunction = fragment;
    descriptor.colorAttachments[0].pixelFormat = MTLPixelFormatRGBA8Unorm;

    NSError *error = nil;
    id<MTLRenderPipelineState> pipeline = [device newRenderPipelineStateWithDescriptor:descriptor error:&error];
    if (pipeline == nil) {
        ite_write_error(error_buf, error_buf_len, error.localizedDescription ?: @"unable to create pipeline");
        return NULL;
    }

    IteMetalRenderer *renderer = calloc(1, sizeof(IteMetalRenderer));
    renderer->device = [device retain];
    renderer->command_queue = [command_queue retain];
    renderer->library = [library retain];
    renderer->pipeline = pipeline;
    return renderer;
}

int ite_metal_present_drawable(void *command_queue_handle, void *drawable_handle, char *error_buf, size_t error_buf_len) {
    id<MTLCommandQueue> command_queue = (__bridge id<MTLCommandQueue>)command_queue_handle;
    id<MTLDrawable> drawable = (__bridge id<MTLDrawable>)drawable_handle;
    if (command_queue == nil || drawable == nil) {
        ite_write_error(error_buf, error_buf_len, @"missing drawable presentation arguments");
        return 0;
    }

    id<MTLCommandBuffer> command_buffer = ite_metal_create_command_buffer(command_queue, error_buf, error_buf_len);
    if (command_buffer == nil) {
        return 0;
    }

    return ite_metal_finalize_command_buffer(command_buffer, drawable, error_buf, error_buf_len);
}

static int ite_metal_renderer_encode_draw(
    IteMetalRenderer *renderer,
    id<MTLCommandBuffer> command_buffer,
    id<MTLTexture> texture,
    const ite_CameraUniform *camera,
    const ite_Rect *rects,
    uint32_t rect_count,
    char *error_buf,
    size_t error_buf_len
) {
    if (renderer == NULL || command_buffer == nil || texture == nil || camera == NULL) {
        ite_write_error(error_buf, error_buf_len, @"missing renderer draw arguments");
        return 0;
    }

    MTLRenderPassDescriptor *pass = [MTLRenderPassDescriptor renderPassDescriptor];
    pass.colorAttachments[0].texture = texture;
    pass.colorAttachments[0].loadAction = MTLLoadActionClear;
    pass.colorAttachments[0].storeAction = MTLStoreActionStore;
    pass.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 1);

    id<MTLRenderCommandEncoder> encoder = [command_buffer renderCommandEncoderWithDescriptor:pass];
    if (encoder == nil) {
        ite_write_error(error_buf, error_buf_len, @"unable to create render command encoder");
        return 0;
    }

    [encoder setRenderPipelineState:renderer->pipeline];
    [encoder setVertexBytes:camera length:sizeof(ite_CameraUniform) atIndex:0];
    if (rect_count > 0) {
        [encoder setVertexBytes:rects length:sizeof(ite_Rect) * rect_count atIndex:1];
        [encoder drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:6 instanceCount:rect_count];
    }
    [encoder endEncoding];

    return 1;
}

int ite_metal_renderer_draw(
    void *renderer_handle,
    void *texture_handle,
    const ite_CameraUniform *camera,
    const ite_Rect *rects,
    uint32_t rect_count,
    char *error_buf,
    size_t error_buf_len
) {
    IteMetalRenderer *renderer = (IteMetalRenderer *)renderer_handle;
    id<MTLTexture> texture = (__bridge id<MTLTexture>)texture_handle;
    id<MTLCommandBuffer> command_buffer = ite_metal_create_command_buffer(renderer != NULL ? renderer->command_queue : nil, error_buf, error_buf_len);
    if (command_buffer == nil) {
        return 0;
    }

    if (!ite_metal_renderer_encode_draw(renderer, command_buffer, texture, camera, rects, rect_count, error_buf, error_buf_len)) {
        return 0;
    }

    return ite_metal_finalize_command_buffer(command_buffer, nil, error_buf, error_buf_len);
}

int ite_metal_renderer_draw_to_drawable(
    void *renderer_handle,
    void *drawable_handle,
    const ite_CameraUniform *camera,
    const ite_Rect *rects,
    uint32_t rect_count,
    char *error_buf,
    size_t error_buf_len
) {
    IteMetalRenderer *renderer = (IteMetalRenderer *)renderer_handle;
    id<CAMetalDrawable> drawable = (__bridge id<CAMetalDrawable>)drawable_handle;
    if (drawable == nil) {
        ite_write_error(error_buf, error_buf_len, @"missing drawable");
        return 0;
    }

    id<MTLCommandBuffer> command_buffer = ite_metal_create_command_buffer(renderer != NULL ? renderer->command_queue : nil, error_buf, error_buf_len);
    if (command_buffer == nil) {
        return 0;
    }

    if (!ite_metal_renderer_encode_draw(renderer, command_buffer, drawable.texture, camera, rects, rect_count, error_buf, error_buf_len)) {
        return 0;
    }

    return ite_metal_finalize_command_buffer(command_buffer, drawable, error_buf, error_buf_len);
}

int ite_metal_texture_read_rgba8(
    void *texture_handle,
    uint8_t *out_pixels,
    size_t out_pixels_len,
    char *error_buf,
    size_t error_buf_len
) {
    id<MTLTexture> texture = (__bridge id<MTLTexture>)texture_handle;
    if (texture == nil || out_pixels == NULL) {
        ite_write_error(error_buf, error_buf_len, @"missing texture readback arguments");
        return 0;
    }

    NSUInteger bytes_per_row = texture.width * 4;
    NSUInteger bytes_needed = bytes_per_row * texture.height;
    if (out_pixels_len < bytes_needed) {
        ite_write_error(error_buf, error_buf_len, @"readback buffer too small");
        return 0;
    }

    MTLRegion region = MTLRegionMake2D(0, 0, texture.width, texture.height);
    [texture getBytes:out_pixels bytesPerRow:bytes_per_row fromRegion:region mipmapLevel:0];
    return 1;
}
