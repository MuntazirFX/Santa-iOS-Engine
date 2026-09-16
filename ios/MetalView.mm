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
    NSData *tgaData = [GameEngine loadTGATextureData];
    if (!tgaData || tgaData.length == 0) {
        NSLog(@"[MetalView] Failed to load TGA data!");
        return;
    }
    
    uint16_t width = 64;
    uint16_t height = 64;
    
    MTLTextureDescriptor *texDesc = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatBGRA8Unorm width:width height:height mipmapped:NO];
    texDesc.usage = MTLTextureUsageShaderRead;
    
    _texture = [_device newTextureWithDescriptor:texDesc];
    if (!_texture) {
        NSLog(@"[MetalView] Failed to create MTLTexture!");
        return;
    }
    
    [_texture replaceRegion:MTLRegionMake2D(0, 0, width, height)
                mipmapLevel:0
                  withBytes:tgaData.bytes
                bytesPerRow:width * 4];
    
    NSLog(@"[MetalView] Texture created: %dx%d", width, height);
}

- (void)mtkView:(MTKView *)view drawableSizeWillChange:(CGSize)size {}

- (void)drawInMTKView:(MTKView *)view {
    if (!_pipelineState) return;
    
    _frameCount++;
    if (_frameCount <= 3) NSLog(@"[MetalView] draw frame %d", _frameCount);
    
    // Vertex data: X, Y, Z, W, U, V (6 floats per vertex)
    static const float vertices[] = {
        // Position              UV
         0.0,  0.8, 0.0, 1.0,    0.5, 0.0,   // Top
        -0.8, -0.8, 0.0, 1.0,    0.0, 1.0,   // Bottom-left
         0.8, -0.8, 0.0, 1.0,    1.0, 1.0,   // Bottom-right
    };
    
    MTLRenderPassDescriptor *rpd = view.currentRenderPassDescriptor;
    if (!rpd) return;
    
    id<MTLCommandBuffer> cmdBuf = [_commandQueue commandBuffer];
    id<MTLRenderCommandEncoder> enc = [cmdBuf renderCommandEncoderWithDescriptor:rpd];
    
    [enc setRenderPipelineState:_pipelineState];
    [enc setVertexBytes:vertices length:sizeof(vertices) atIndex:0];
    [enc setFragmentTexture:_texture atIndex:0];
    [enc setFragmentSamplerState:_sampler atIndex:0];
    [enc drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:3];
    [enc endEncoding];
    
    [cmdBuf presentDrawable:view.currentDrawable];
    [cmdBuf commit];
}

@end
