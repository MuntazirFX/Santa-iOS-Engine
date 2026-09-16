#import "MetalView.h"
#import <Metal/Metal.h>
#import <simd/simd.h>

@implementation MetalView {
    id<MTLDevice> _device;
    id<MTLCommandQueue> _commandQueue;
    id<MTLRenderPipelineState> _pipelineState;
    int _frameCount;
}

- (instancetype)initWithFrame:(CGRect)frame {
    NSLog(@"[MetalView] init with frame: %.0fx%.0f", frame.size.width, frame.size.height);
    
    _device = MTLCreateSystemDefaultDevice();
    if (!_device) {
        NSLog(@"[MetalView] ERROR: No Metal device!");
        return nil;
    }
    NSLog(@"[MetalView] Device: %@", _device.name);
    
    self = [super initWithFrame:frame device:_device];
    if (self) {
        self.clearColor = MTLClearColorMake(0.2, 0.2, 0.5, 1.0); // Brighter blue for visibility
        self.colorPixelFormat = MTLPixelFormatBGRA8Unorm;
        self.preferredFramesPerSecond = 60;
        self.delegate = self;
        self.paused = NO;
        self.enableSetNeedsDisplay = NO;
        
        _frameCount = 0;
        _commandQueue = [_device newCommandQueue];
        
        // Shader library load karein
        id<MTLLibrary> library = [_device newDefaultLibrary];
        if (!library) {
            NSLog(@"[MetalView] ERROR: newDefaultLibrary returned nil!");
            return self;
        }
        NSLog(@"[MetalView] Library loaded. Functions: %@", [library functionNames]);
        
        id<MTLFunction> vertexFunction = [library newFunctionWithName:@"vertex_main"];
        id<MTLFunction> fragmentFunction = [library newFunctionWithName:@"fragment_main"];
        
        if (!vertexFunction) {
            NSLog(@"[MetalView] ERROR: vertex_main not found!");
            return self;
        }
        if (!fragmentFunction) {
            NSLog(@"[MetalView] ERROR: fragment_main not found!");
            return self;
        }
        NSLog(@"[MetalView] Both shader functions found!");
        
        MTLRenderPipelineDescriptor *pipelineDescriptor = [[MTLRenderPipelineDescriptor alloc] init];
        pipelineDescriptor.vertexFunction = vertexFunction;
        pipelineDescriptor.fragmentFunction = fragmentFunction;
        pipelineDescriptor.colorAttachments[0].pixelFormat = self.colorPixelFormat;
        
        NSError *error = nil;
        _pipelineState = [_device newRenderPipelineStateWithDescriptor:pipelineDescriptor error:&error];
        if (!_pipelineState) {
            NSLog(@"[MetalView] ERROR: Pipeline failed: %@", error);
        } else {
            NSLog(@"[MetalView] Pipeline created successfully!");
        }
    }
    return self;
}

- (void)mtkView:(MTKView *)view drawableSizeWillChange:(CGSize)size {
    NSLog(@"[MetalView] Drawable size changed: %.0fx%.0f", size.width, size.height);
}

- (void)drawInMTKView:(MTKView *)view {
    if (!_pipelineState) return;
    
    _frameCount++;
    if (_frameCount <= 3) {
        NSLog(@"[MetalView] drawInMTKView called (frame %d)", _frameCount);
    }
    
    static const float vertices[] = {
         0.0,  0.8, 0.0, 1.0,       1.0, 0.0, 0.0, 1.0,
        -0.8, -0.8, 0.0, 1.0,       0.0, 1.0, 0.0, 1.0,
         0.8, -0.8, 0.0, 1.0,       0.0, 0.0, 1.0, 1.0,
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
