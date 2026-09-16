#import "MetalView.h"
#import "GameEngine.h"
#import <Metal/Metal.h>

@implementation MetalView {
    id<MTLDevice> _device;
    id<MTLCommandQueue> _commandQueue;
    id<MTLRenderPipelineState> _meshPipelineState;
    id<MTLTexture> _texture;
    id<MTLSamplerState> _sampler;
    id<MTLDepthStencilState> _depthState;
    id<MTLTexture> _depthTexture;
    id<MTLBuffer> _vertexBuffer;
    id<MTLBuffer> _indexBuffer;
    int _indexCount;
    int _frameCount;
    float _angle;
}

- (instancetype)initWithFrame:(CGRect)frame {
    _device = MTLCreateSystemDefaultDevice();
    self = [super initWithFrame:frame device:_device];
    if (self) {
        self.clearColor = MTLClearColorMake(0.05, 0.05, 0.15, 1.0);
        self.colorPixelFormat = MTLPixelFormatBGRA8Unorm;
        self.depthStencilPixelFormat = MTLPixelFormatDepth32Float;
        self.preferredFramesPerSecond = 60;
        self.delegate = self;
        self.paused = NO;
        self.enableSetNeedsDisplay = NO;
        
        _frameCount = 0;
        _angle = 0;
        _indexCount = 0;
        _commandQueue = [_device newCommandQueue];
        
        MTLSamplerDescriptor *sampDesc = [[MTLSamplerDescriptor alloc] init];
        sampDesc.minFilter = MTLSamplerMinMagFilterLinear;
        sampDesc.magFilter = MTLSamplerMinMagFilterLinear;
        sampDesc.sAddressMode = MTLSamplerAddressModeRepeat;
        sampDesc.tAddressMode = MTLSamplerAddressModeRepeat;
        _sampler = [_device newSamplerStateWithDescriptor:sampDesc];
        
        MTLDepthStencilDescriptor *depthDesc = [[MTLDepthStencilDescriptor alloc] init];
        depthDesc.depthCompareFunction = MTLCompareFunctionLess;
        depthDesc.depthWriteEnabled = YES;
        _depthState = [_device newDepthStencilStateWithDescriptor:depthDesc];
        
        id<MTLLibrary> library = [_device newDefaultLibrary];
        id<MTLFunction> vf = [library newFunctionWithName:@"mesh_vertex"];
        id<MTLFunction> ff = [library newFunctionWithName:@"mesh_fragment"];
        
        MTLRenderPipelineDescriptor *desc = [[MTLRenderPipelineDescriptor alloc] init];
        desc.vertexFunction = vf;
        desc.fragmentFunction = ff;
        desc.colorAttachments[0].pixelFormat = self.colorPixelFormat;
        desc.depthAttachmentPixelFormat = self.depthStencilPixelFormat;
        
        NSError *err = nil;
        _meshPipelineState = [_device newRenderPipelineStateWithDescriptor:desc error:&err];
        if (!_meshPipelineState) NSLog(@"[MetalView] Pipeline failed: %@", err);
        else NSLog(@"[MetalView] Textured pipeline ready");
    }
    return self;
}

- (id<MTLTexture>)loadTGATextureNamed:(NSString *)name {
    NSData *tgaData = [GameEngine loadAssetNamed:name];
    if (!tgaData || tgaData.length < 18) {
        NSLog(@"[MetalView] TGA not found: %@", name);
        return nil;
    }
    
    const uint8_t *bytes = (const uint8_t *)tgaData.bytes;
    uint16_t width = bytes[12] | (bytes[13] << 8);
    uint16_t height = bytes[14] | (bytes[15] << 8);
    uint8_t bpp = bytes[16];
    
    NSLog(@"[MetalView] Loading TGA: %@ (%dx%d @ %dbpp)", name, width, height, bpp);
    
    MTLTextureDescriptor *texDesc = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatBGRA8Unorm width:width height:height mipmapped:NO];
    texDesc.usage = MTLTextureUsageShaderRead;
    id<MTLTexture> tex = [_device newTextureWithDescriptor:texDesc];
    
    if (tex) {
        [tex replaceRegion:MTLRegionMake2D(0, 0, width, height)
                mipmapLevel:0
                  withBytes:(bytes + 18)
                bytesPerRow:width * (bpp / 8)];
    }
    return tex;
}

- (void)setMeshToRender:(MeshData *)mesh {
    if (!mesh || mesh.vertexCount == 0) return;
    
    const float *verts = (const float *)mesh.vertices.bytes;
    const float *uvs = (const float *)mesh.uvs.bytes;
    const uint32_t *faces = (const uint32_t *)mesh.indices.bytes;
    
    // Bounding box for normalization
    float minX = 1e9, maxX = -1e9, minY = 1e9, maxY = -1e9, minZ = 1e9, maxZ = -1e9;
    for (int i = 0; i < mesh.vertexCount; i++) {
        float x = verts[i*3], y = verts[i*3+1], z = verts[i*3+2];
        if (x < minX) minX = x; if (x > maxX) maxX = x;
        if (y < minY) minY = y; if (y > maxY) maxY = y;
        if (z < minZ) minZ = z; if (z > maxZ) maxZ = z;
    }
    float cx = (minX+maxX)/2, cy = (minY+maxY)/2, cz = (minZ+maxZ)/2;
    float maxDim = fmaxf(maxX-minX, fmaxf(maxY-minY, maxZ-minZ));
    float scale = 1.6f / maxDim;
    
    // Interleave vertices + UVs (5 floats per vertex)
    float *vbuf = new float[mesh.vertexCount * 5];
    for (int i = 0; i < mesh.vertexCount; i++) {
        vbuf[i*5+0] = (verts[i*3+0] - cx) * scale;
        vbuf[i*5+1] = (verts[i*3+1] - cy) * scale;
        vbuf[i*5+2] = (verts[i*3+2] - cz) * scale;
        if (uvs) {
            vbuf[i*5+3] = uvs[i*2+0];
            vbuf[i*5+4] = 1.0f - uvs[i*2+1]; // V-flip
        } else {
            vbuf[i*5+3] = 0.5f;
            vbuf[i*5+4] = 0.5f;
        }
    }
    _vertexBuffer = [_device newBufferWithBytes:vbuf length:mesh.vertexCount*5*sizeof(float) options:MTLResourceStorageModeShared];
    delete[] vbuf;
    
    // Index buffer
    _indexBuffer = [_device newBufferWithBytes:faces length:mesh.faceCount*3*sizeof(uint32_t) options:MTLResourceStorageModeShared];
    _indexCount = mesh.faceCount * 3;
    
    // Load texture
    if (mesh.textureName) {
        // Extract filename from full path (e.g., "D:\...\haus2.tga" → "haus2.tga")
        NSString *fullPath = mesh.textureName;
        NSString *filename = [fullPath lastPathComponent];
        NSLog(@"[MetalView] Texture referenced: %@", filename);
        
        // Try different XPK paths
        NSArray *tryPaths = @[
            [NSString stringWithFormat:@"maps\\%@", filename],
            filename,
            [NSString stringWithFormat:@"maps\\%@", [filename stringByReplacingOccurrencesOfString:@".tga" withString:@".dds"]],
        ];
        for (NSString *p in tryPaths) {
            _texture = [self loadTGATextureNamed:p];
            if (_texture) break;
        }
    }
    
    if (!_texture) {
        // Fallback
        _texture = [self loadTGATextureNamed:@"maps\\mouse.tga"];
    }
    
    NSLog(@"[MetalView] Mesh ready: %d verts, %d indices, texture: %@",
          mesh.vertexCount, _indexCount, _texture ? @"YES" : @"NO");
}

- (void)mtkView:(MTKView *)view drawableSizeWillChange:(CGSize)size {
    // Recreate depth texture
    MTLTextureDescriptor *desc = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatDepth32Float width:size.width height:size.height mipmapped:NO];
    desc.usage = MTLTextureUsageRenderTarget;
    desc.storageMode = MTLStorageModePrivate;
    _depthTexture = [_device newTextureWithDescriptor:desc];
}

- (void)drawInMTKView:(MTKView *)view {
    if (!_meshPipelineState || _indexCount == 0) return;
    
    _frameCount++;
    _angle += 0.01f; // Rotation speed
    
    if (_frameCount <= 5) NSLog(@"[MetalView] Draw frame %d", _frameCount);
    
    // Ensure depth texture
    if (!_depthTexture) {
        CGSize s = view.drawableSize;
        MTLTextureDescriptor *desc = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatDepth32Float width:s.width height:s.height mipmapped:NO];
        desc.usage = MTLTextureUsageRenderTarget;
        _depthTexture = [_device newTextureWithDescriptor:desc];
    }
    
    MTLRenderPassDescriptor *rpd = view.currentRenderPassDescriptor;
    if (!rpd) return;
    
    rpd.depthAttachment.texture = _depthTexture;
    rpd.depthAttachment.clearDepth = 1.0;
    rpd.depthAttachment.loadAction = MTLLoadActionClear;
    rpd.depthAttachment.storeAction = MTLStoreActionDontCare;
    
    id<MTLCommandBuffer> cmdBuf = [_commandQueue commandBuffer];
    id<MTLRenderCommandEncoder> enc = [cmdBuf renderCommandEncoderWithDescriptor:rpd];
    
    [enc setRenderPipelineState:_meshPipelineState];
    [enc setDepthStencilState:_depthState];
    [enc setVertexBuffer:_vertexBuffer offset:0 atIndex:0];
    [enc setVertexBytes:&_angle length:sizeof(float) atIndex:1];
    [enc setFragmentTexture:_texture atIndex:0];
    [enc setFragmentSamplerState:_sampler atIndex:0];
    [enc drawIndexedPrimitives:MTLPrimitiveTypeTriangle
                    indexCount:_indexCount
                     indexType:MTLIndexTypeUInt32
                   indexBuffer:_indexBuffer
             indexBufferOffset:0];
    [enc endEncoding];
    
    [cmdBuf presentDrawable:view.currentDrawable];
    [cmdBuf commit];
}

@end
