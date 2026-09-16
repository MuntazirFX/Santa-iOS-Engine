#import "MetalView.h"
#import <Metal/Metal.h>
#import <simd/simd.h>

@implementation MetalView {
    id<MTLDevice> _device;
    id<MTLCommandQueue> _commandQueue;
    id<MTLRenderPipelineState> _pipelineState;
}

- (instancetype)initWithFrame:(CGRect)frame {
    _device = MTLCreateSystemDefaultDevice();
    self = [super initWithFrame:frame device:_device];
    if (self) {
        self.clearColor = MTLClearColorMake(0.1, 0.1, 0.2, 1.0);
        self.colorPixelFormat = MTLPixelFormatBGRA8Unorm;
        self.preferredFramesPerSecond = 60;
        self.delegate = self;
        
        _commandQueue = [_device newCommandQueue];
        
        // Shader library load karein (default.metallib)
        NSError *error = nil;
        id<MTLLibrary> library = [_device newDefaultLibrary];
        if (!library) {
            NSLog(@"[MetalView] ERROR: Could not load default library!");
            return self;
        }
        
        // Vertex aur fragment functions dhoondein
        id<MTLFunction> vertexFunction = [library newFunctionWithName:@"vertex_main"];
        id<MTLFunction> fragmentFunction = [library newFunctionWithName:@"fragment_main"];
        
        if (!vertexFunction || !fragmentFunction) {
            NSLog(@"[MetalView] ERROR: Could not find shader functions!");
            return self;
        }
        
        // Render pipeline descriptor banayein
        MTLRenderPipelineDescriptor *pipelineDescriptor = [[MTLRenderPipelineDescriptor alloc] init];
        pipelineDescriptor.vertexFunction = vertexFunction;
        pipelineDescriptor.fragmentFunction = fragmentFunction;
        pipelineDescriptor.colorAttachments[0].pixelFormat = self.colorPixelFormat;
        
        _pipelineState = [_device newRenderPipelineStateWithDescriptor:pipelineDescriptor error:&error];
        if (!_pipelineState) {
            NSLog(@"[MetalView] ERROR: Pipeline creation failed: %@", error);
        } else {
            NSLog(@"[MetalView] Pipeline created successfully!");
        }
    }
    return self;
}

- (void)mtkView:(MTKView *)view drawableSizeWillChange:(CGSize)size {
}

- (void)drawInMTKView:(MTKView *)view {
    if (!_pipelineState) return;
    
    // Triangle ke 3 vertices (X, Y, Z, W, R, G, B, A)
    // Screen coordinates: -1 to 1
    static const float vertices[] = {
        // Position (X, Y, Z, W)     Color (R, G, B, A)
         0.0,  0.8, 0.0, 1.0,       1.0, 0.0, 0.0, 1.0,  // Top (Red)
        -0.8, -0.8, 0.0, 1.0,       0.0, 1.0, 0.0, 1.0,  // Bottom-left (Green)
         0.8, -0.8, 0.0, 1.0,       0.0, 0.0, 1.0, 1.0,  // Bottom-right (Blue)
    };
    
    MTLRenderPassDescriptor *renderPassDescriptor = view.currentRenderPassDescriptor;
    if (renderPassDescriptor == nil) return;
    
    id<MTLCommandBuffer> commandBuffer = [_commandQueue commandBuffer];
    id<MTLRenderCommandEncoder> encoder = [commandBuffer renderCommandEncoderWithDescriptor:renderPassDescriptor];
    
    [encoder setRenderPipelineState:_pipelineState];
    [encoder setVertexBytes:vertices length:sizeof(vertices) atIndex:0];
    [encoder drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:3];
    [encoder endEncoding];
    
    [commandBuffer presentDrawable:view.currentDrawable];
    [commandBuffer commit];
}

@end
