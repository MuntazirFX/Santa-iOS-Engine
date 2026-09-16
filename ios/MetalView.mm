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
    CGSize _lastDrawableSize;
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
        _lastDrawableSize = CGSizeZero;
        _commandQueue = [_device newCommandQueue];
        
        MTLSamplerDescriptor *sampDesc = [[MTLSamplerDescriptor alloc] init];
        sampDesc.minFilter = MTLSamplerMinMagFilterLinear;
        sampDesc.magFilter = MTLSamplerMinMagFilterLinear;
        sampDesc.sAddressMode = MTLSamplerAddressModeClampToEdge;
        sampDesc.tAddressMode = MTLSamplerAddressModeClampToEdge;
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
        else NSLog(@"[MetalView] Pipeline ready");
    }
    return self;
}

#pragma mark - TGA Loader

- (id<MTLTexture>)loadTGATextureNamed:(NSString *)name {
    NSData *tgaData = [GameEngine loadAssetNamed:name];
    if (!tgaData || tgaData.length < 18) return nil;
    
    const uint8_t *bytes = (const uint8_t *)tgaData.bytes;
    uint16_t width = bytes[12] | (bytes[13] << 8);
    uint16_t height = bytes[14] | (bytes[15] << 8);
    uint8_t bpp = bytes[16];
    
    if (width == 0 || height == 0 || (bpp != 24 && bpp != 32)) return nil;
    
    NSLog(@"[Texture] TGA: %@ (%dx%d @ %dbpp)", name, width, height, bpp);
    
    MTLTextureDescriptor *texDesc = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatBGRA8Unorm width:width height:height mipmapped:NO];
    texDesc.usage = MTLTextureUsageShaderRead;
    id<MTLTexture> tex = [_device newTextureWithDescriptor:texDesc];
    if (!tex) return nil;
    
    if (bpp == 24) {
        size_t pixelCount = width * height;
        uint8_t *rgba = new uint8_t[pixelCount * 4];
        const uint8_t *src = bytes + 18;
        for (size_t i = 0; i < pixelCount; i++) {
            rgba[i*4+0] = src[i*3+0];
            rgba[i*4+1] = src[i*3+1];
            rgba[i*4+2] = src[i*3+2];
            rgba[i*4+3] = 255;
        }
        [tex replaceRegion:MTLRegionMake2D(0, 0, width, height) mipmapLevel:0 withBytes:rgba bytesPerRow:width * 4];
        delete[] rgba;
    } else {
        [tex replaceRegion:MTLRegionMake2D(0, 0, width, height) mipmapLevel:0 withBytes:(bytes + 18) bytesPerRow:width * 4];
    }
    return tex;
}

#pragma mark - DDS Loader

- (id<MTLTexture>)loadDDSTextureNamed:(NSString *)name {
    NSData *ddsData = [GameEngine loadAssetNamed:name];
    if (!ddsData || ddsData.length < 128) {
        NSLog(@"[Texture] DDS not found: %@", name);
        return nil;
    }
    
    const uint8_t *bytes = (const uint8_t *)ddsData.bytes;
    
    // Check magic "DDS "
    if (bytes[0] != 'D' || bytes[1] != 'D' || bytes[2] != 'S' || bytes[3] != ' ') {
        NSLog(@"[Texture] Not a DDS file: %@", name);
        return nil;
    }
    
    uint32_t height = *(uint32_t *)(bytes + 12);
    uint32_t width = *(uint32_t *)(bytes + 16);
    uint32_t pitch = *(uint32_t *)(bytes + 20);
    uint32_t mipCount = *(uint32_t *)(bytes + 28);
    if (mipCount == 0) mipCount = 1;
    
    // Pixel format (at offset 76)
    uint32_t pfSize = *(uint32_t *)(bytes + 76);
    uint32_t pfFlags = *(uint32_t *)(bytes + 80);
    uint32_t fourCC = *(uint32_t *)(bytes + 84);
    uint32_t rgbBitCount = *(uint32_t *)(bytes + 88);
    uint32_t rMask = *(uint32_t *)(bytes + 92);
    uint32_t gMask = *(uint32_t *)(bytes + 96);
    uint32_t bMask = *(uint32_t *)(bytes + 100);
    uint32_t aMask = *(uint32_t *)(bytes + 104);
    
    NSLog(@"[Texture] DDS: %@ (%ux%u, mips=%u, pfFlags=0x%x, bitCount=%u, fourCC=0x%x)",
          name, width, height, mipCount, pfFlags, rgbBitCount, fourCC);
    NSLog(@"[Texture]   R=0x%x G=0x%x B=0x%x A=0x%x", rMask, gMask, bMask, aMask);
    
    MTLTextureDescriptor *texDesc = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatBGRA8Unorm width:width height:height mipmapped:NO];
    texDesc.usage = MTLTextureUsageShaderRead;
    id<MTLTexture> tex = [_device newTextureWithDescriptor:texDesc];
    if (!tex) {
        NSLog(@"[Texture] Failed to create MTLTexture");
        return nil;
    }
    
    // Uncompressed formats only (FourCC == 0)
    if (fourCC != 0 && fourCC != 0x30315844) {
        // 0x30315844 = "DX10" extended header — for now skip
        NSLog(@"[Texture] Compressed DDS (DXT) not supported yet, fourCC=0x%x", fourCC);
        return nil;
    }
    
    const uint8_t *pixelData = bytes + 128;
    size_t pixelDataAvailable = ddsData.length - 128;
    size_t expectedPixels = width * height * 4;
    
    if (rgbBitCount == 32) {
        // 32-bit: already RGBA-ish, but channel order may vary
        // Most DDS use A8R8G8B8 (which is BGRA in little-endian)
        // Metal MTLPixelFormatBGRA8Unorm expects: B, G, R, A in memory
        // If DDS has A8R8G8B8: bytes are B, G, R, A — matches directly
        
        if (pixelDataAvailable < expectedPixels) {
            NSLog(@"[Texture] DDS data too small");
            return nil;
        }
        
        [tex replaceRegion:MTLRegionMake2D(0, 0, width, height)
                mipmapLevel:0
                  withBytes:pixelData
                bytesPerRow:width * 4];
    } else if (rgbBitCount == 24) {
        // 24-bit: convert to 32
        size_t pixelCount = width * height;
        uint8_t *rgba = new uint8_t[pixelCount * 4];
        for (size_t i = 0; i < pixelCount; i++) {
            // Assume BGR layout (most common)
            rgba[i*4+0] = pixelData[i*3+0]; // B
            rgba[i*4+1] = pixelData[i*3+1]; // G
            rgba[i*4+2] = pixelData[i*3+2]; // R
            rgba[i*4+3] = 255;
        }
        [tex replaceRegion:MTLRegionMake2D(0, 0, width, height) mipmapLevel:0 withBytes:rgba bytesPerRow:width * 4];
        delete[] rgba;
    } else {
        NSLog(@"[Texture] Unsupported bit count: %u", rgbBitCount);
        return nil;
    }
    
    NSLog(@"[Texture] ✓ DDS loaded: %@", name);
    return tex;
}

#pragma mark - Universal Texture Loader

- (id<MTLTexture>)loadTextureNamed:(NSString *)name {
    NSString *lower = [name lowercaseString];
    if ([lower hasSuffix:@".dds"]) {
        return [self loadDDSTextureNamed:name];
    } else if ([lower hasSuffix:@".tga"]) {
        return [self loadTGATextureNamed:name];
    }
    return nil;
}

- (id<MTLTexture>)whiteTexture {
    MTLTextureDescriptor *desc = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatBGRA8Unorm width:1 height:1 mipmapped:NO];
    desc.usage = MTLTextureUsageShaderRead;
    id<MTLTexture> tex = [_device newTextureWithDescriptor:desc];
    uint8_t white[4] = {255, 255, 255, 255};
    [tex replaceRegion:MTLRegionMake2D(0, 0, 1, 1) mipmapLevel:0 withBytes:white bytesPerRow:4];
    return tex;
}

#pragma mark - Setup Mesh

- (void)setMeshToRender:(MeshData *)mesh {
    if (!mesh || mesh.vertexCount <= 0 || mesh.faceCount <= 0) return;
    
    const float *verts = (const float *)mesh.vertices.bytes;
    const float *uvs = mesh.uvs ? (const float *)mesh.uvs.bytes : NULL;
    const uint32_t *faces = (const uint32_t *)mesh.indices.bytes;
    
    float minX = 1e9, maxX = -1e9, minY = 1e9, maxY = -1e9, minZ = 1e9, maxZ = -1e9;
    for (int i = 0; i < mesh.vertexCount; i++) {
        float x = verts[i*3], y = verts[i*3+1], z = verts[i*3+2];
        if (x < minX) minX = x; if (x > maxX) maxX = x;
        if (y < minY) minY = y; if (y > maxY) maxY = y;
        if (z < minZ) minZ = z; if (z > maxZ) maxZ = z;
    }
    float cx = (minX+maxX)/2, cy = (minY+maxY)/2, cz = (minZ+maxZ)/2;
    float maxDim = fmaxf(maxX-minX, fmaxf(maxY-minY, maxZ-minZ));
    if (maxDim < 0.001f) return;
    float scale = 1.4f / maxDim;
    
    float *vbuf = new float[mesh.vertexCount * 5];
    for (int i = 0; i < mesh.vertexCount; i++) {
        vbuf[i*5+0] = (verts[i*3+0] - cx) * scale;
        vbuf[i*5+1] = (verts[i*3+1] - cy) * scale;
        vbuf[i*5+2] = (verts[i*3+2] - cz) * scale;
        if (uvs) {
            vbuf[i*5+3] = uvs[i*2+0];
            vbuf[i*5+4] = 1.0f - uvs[i*2+1];
        } else {
            vbuf[i*5+3] = 0.5f;
            vbuf[i*5+4] = 0.5f;
        }
    }
    _vertexBuffer = [_device newBufferWithBytes:vbuf length:mesh.vertexCount*5*sizeof(float) options:MTLResourceStorageModeShared];
    delete[] vbuf;
    
    _indexBuffer = [_device newBufferWithBytes:faces length:mesh.faceCount*3*sizeof(uint32_t) options:MTLResourceStorageModeShared];
    _indexCount = mesh.faceCount * 3;
    
    // ====== Texture loading (DDS + TGA) ======
    _texture = nil;
    if (mesh.textureName && mesh.textureName.length > 0) {
        NSString *filename = [mesh.textureName lastPathComponent]; // "haus2.tga"
        NSString *basename = [filename stringByDeletingPathExtension]; // "haus2"
        
        // Try DDS first (game shipped as DDS), then TGA
        NSArray *tryPaths = @[
            [NSString stringWithFormat:@"maps\\%@.dds", basename],
            [NSString stringWithFormat:@"maps\\%@.tga", basename],
            [NSString stringWithFormat:@"%@.dds", basename],
            [NSString stringWithFormat:@"%@.tga", basename],
            filename,
            [NSString stringWithFormat:@"maps\\%@", filename],
        ];
        
        for (NSString *p in tryPaths) {
            NSLog(@"[MetalView] Trying texture: %@", p);
            _texture = [self loadTextureNamed:p];
            if (_texture) break;
        }
    }
    
    if (!_texture) {
        NSLog(@"[MetalView] Using white fallback");
        _texture = [self whiteTexture];
    }
    
    NSLog(@"[MetalView] Mesh ready: %d verts, %d idx, texture: %@",
          mesh.vertexCount, _indexCount, _texture ? @"YES" : @"NO");
}

- (void)mtkView:(MTKView *)view drawableSizeWillChange:(CGSize)size {
    if (size.width <= 0 || size.height <= 0) return;
    MTLTextureDescriptor *desc = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatDepth32Float width:size.width height:size.height mipmapped:NO];
    desc.usage = MTLTextureUsageRenderTarget;
    desc.storageMode = MTLStorageModePrivate;
    _depthTexture = [_device newTextureWithDescriptor:desc];
    _lastDrawableSize = size;
}

- (void)drawInMTKView:(MTKView *)view {
    if (!_meshPipelineState || _indexCount <= 0) return;
    if (!_vertexBuffer || !_indexBuffer) return;
    
    CGSize ds = view.drawableSize;
    if (ds.width <= 0 || ds.height <= 0) return;
    
    if (!_depthTexture || !CGSizeEqualToSize(_lastDrawableSize, ds)) {
        MTLTextureDescriptor *desc = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatDepth32Float width:ds.width height:ds.height mipmapped:NO];
        desc.usage = MTLTextureUsageRenderTarget;
        desc.storageMode = MTLStorageModePrivate;
        _depthTexture = [_device newTextureWithDescriptor:desc];
        _lastDrawableSize = ds;
    }
    
    _frameCount++;
    _angle += 0.01f;
    
    MTLRenderPassDescriptor *rpd = view.currentRenderPassDescriptor;
    if (!rpd) return;
    
    rpd.depthAttachment.texture = _depthTexture;
    rpd.depthAttachment.clearDepth = 1.0;
    rpd.depthAttachment.loadAction = MTLLoadActionClear;
    rpd.depthAttachment.storeAction = MTLStoreActionDontCare;
    
    id<MTLCommandBuffer> cmdBuf = [_commandQueue commandBuffer];
    if (!cmdBuf) return;
    
    id<MTLRenderCommandEncoder> enc = [cmdBuf renderCommandEncoderWithDescriptor:rpd];
    if (!enc) return;
    
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
