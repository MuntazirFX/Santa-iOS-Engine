#import "MetalView.h"
#import "GameEngine.h"
#import <Metal/Metal.h>

@implementation MetalView {
    id<MTLDevice> _device;
    id<MTLCommandQueue> _commandQueue;
    id<MTLRenderPipelineState> _pipelineState;
    id<MTLTexture> _texture;
    id<MTLSamplerState> _sampler;
    int _frameCount;
}

- (instancetype)initWithFrame:(CGRect)frame {
    _device = MTLCreateSystemDefaultDevice();
    self = [super initWithFrame:frame device:_device];
    if (self) {
        self.clearColor = MTLClearColorMake(0.1, 0.1, 0.2, 1.0);
        self.colorPixelFormat = MTLPixelFormatBGRA8Unorm;
        self.preferredFramesPerSecond = 60;
        self.delegate = self;
        self.paused = NO;
        self.enableSetNeedsDisplay = NO;
        
        _frameCount = 0;
        _commandQueue = [_device newCommandQueue];
        
        [self createTexture];
        
        // Sampler
        MTLSamplerDescriptor *sampDesc = [[MTLSamplerDescriptor alloc] init];
        sampDesc.minFilter = MTLSamplerMinMagFilterNearest;
        sampDesc.magFilter = MTLSamplerMinMagFilterNearest;
        sampDesc.sAddressMode = MTLSamplerAddressModeClampToEdge;
        sampDesc.tAddressMode = MTLSamplerAddressModeClampToEdge;
        _sampler = [_device newSamplerStateWithDescriptor:sampDesc];
        
        // Pipeline
        id<MTLLibrary> library = [_device newDefaultLibrary];
        id<MTLFunction> vertexFunction = [library newFunctionWithName:@"vertex_main"];
        id<MTLFunction> fragmentFunction = [library newFunctionWithName:@"fragment_main"];
        
        MTLRenderPipelineDescriptor *desc = [[MTLRenderPipelineDescriptor alloc] init];
        desc.vertexFunction = vertexFunction;
        desc.fragmentFunction = fragmentFunction;
        desc.colorAttachments[0].pixelFormat = self.colorPixelFormat;
        
        NSError *error = nil;
        _pipelineState = [_device newRenderPipelineStateWithDescriptor:desc error:&error];
        if (!_pipelineState) {
            NSLog(@"[MetalView] Pipeline failed: %@", error);
        } else {
            NSLog(@"[MetalView] Pipeline ready with texture!");
        }
    }
    return self;
}
 - (void)createTexture {
    // 3D model file (.x) load karke hex dump karein
    NSData *xData = [GameEngine loadAssetNamed:@"gfx\\schneemann_000.x"];
    if (!xData || xData.length == 0) {
        NSLog(@"[MetalView] Failed to load .x file!");
        return;
    }
    
    NSLog(@"[MetalView] .x file size: %lu bytes", (unsigned long)xData.length);
    
    // Pehle 64 bytes hex dump karein
    const uint8_t *bytes = (const uint8_t *)xData.bytes;
    NSMutableString *hexDump = [NSMutableString string];
    for (int i = 0; i < 64 && i < xData.length; i++) {
        [hexDump appendFormat:@"%02x ", bytes[i]];
        if ((i + 1) % 16 == 0) [hexDump appendString:@"\n"];
    }
    NSLog(@"[MetalView] First 64 bytes:\n%@", hexDump);
    
    // ASCII check
    NSMutableString *ascii = [NSMutableString string];
    for (int i = 0; i < 64 && i < xData.length; i++) {
        char c = (char)bytes[i];
        if (c >= 32 && c < 127) {
            [ascii appendFormat:@"%c", c];
        } else {
            [ascii appendString:@"."];
        }
    }
    NSLog(@"[MetalView] ASCII: %@", ascii);
}
}

- (void)mtkView:(MTKView *)view drawableSizeWillChange:(CGSize)size {}

- (void)drawInMTKView:(MTKView *)view {
    if (!_pipelineState) return;
    
    _frameCount++;
    if (_frameCount <= 3) NSLog(@"[MetalView] draw frame %d", _frameCount);
    
// Poora screen cover karne ke liye quad (2 triangles = 6 vertices)
    static const float vertices[] = {
        // Triangle 1 (top-right half)
        // Position              UV
        -1.0,  1.0, 0.0, 1.0,    0.0, 0.0,   // Top-left
         1.0,  1.0, 0.0, 1.0,    1.0, 0.0,   // Top-right
         1.0, -1.0, 0.0, 1.0,    1.0, 1.0,   // Bottom-right
        // Triangle 2 (bottom-left half)
        -1.0,  1.0, 0.0, 1.0,    0.0, 0.0,   // Top-left
         1.0, -1.0, 0.0, 1.0,    1.0, 1.0,   // Bottom-right
        -1.0, -1.0, 0.0, 1.0,    0.0, 1.0,   // Bottom-left
    };
    
    MTLRenderPassDescriptor *rpd = view.currentRenderPassDescriptor;
    if (!rpd) return;
    
    id<MTLCommandBuffer> cmdBuf = [_commandQueue commandBuffer];
    id<MTLRenderCommandEncoder> enc = [cmdBuf renderCommandEncoderWithDescriptor:rpd];
    
    [enc setRenderPipelineState:_pipelineState];
    [enc setVertexBytes:vertices length:sizeof(vertices) atIndex:0];
    [enc setFragmentTexture:_texture atIndex:0];
    [enc setFragmentSamplerState:_sampler atIndex:0];
    [enc drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:6];
    [enc endEncoding];
    
    [cmdBuf presentDrawable:view.currentDrawable];
    [cmdBuf commit];
}

@end
