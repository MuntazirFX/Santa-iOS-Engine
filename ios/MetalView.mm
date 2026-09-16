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
        _textureDebugInfo = @"(not loaded yet)";
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
    }
    return self;
}

#pragma mark - DDS Loader

- (id<MTLTexture>)createTextureFromDDSData:(NSData *)ddsData debug:(NSMutableString *)dbg {
    if (!ddsData || ddsData.length < 128) return nil;
    
    const uint8_t *bytes = (const uint8_t *)ddsData.bytes;
    uint32_t height = *(uint32_t *)(bytes + 12);
    uint32_t width = *(uint32_t *)(bytes + 16);
    uint32_t fourCC = *(uint32_t *)(bytes + 84);
    uint32_t rgbBitCount = *(uint32_t *)(bytes + 88);
    uint32_t rMask = *(uint32_t *)(bytes + 92);
    uint32_t gMask = *(uint32_t *)(bytes + 96);
    uint32_t bMask = *(uint32_t *)(bytes + 100);
    uint32_t aMask = *(uint32_t *)(bytes + 104);
    
    if (fourCC != 0) {
        [dbg appendString:@"  DXT compressed, skip\n"];
        return nil;
    }
    
    if (width == 0 || height == 0 || width > 4096 || height > 4096) return nil;
    
    MTLTextureDescriptor *texDesc = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatBGRA8Unorm width:width height:height mipmapped:NO];
    texDesc.usage = MTLTextureUsageShaderRead;
    id<MTLTexture> tex = [_device newTextureWithDescriptor:texDesc];
    if (!tex) return nil;
    
    const uint8_t *pixelData = bytes + 128;
    size_t availableBytes = ddsData.length - 128;
    size_t neededBytes = width * height * (rgbBitCount / 8);
    if (availableBytes < neededBytes) {
        [dbg appendFormat:@"  Not enough data (%lu < %lu)\n", (unsigned long)availableBytes, (unsigned long)neededBytes];
        return nil;
    }
    
    if (rgbBitCount == 32) {
        [tex replaceRegion:MTLRegionMake2D(0, 0, width, height) mipmapLevel:0 withBytes:pixelData bytesPerRow:width * 4];
        [dbg appendString:@"  ✓ 32-bit\n"];
    } else if (rgbBitCount == 24) {
        size_t pixelCount = width * height;
        uint8_t *rgba = new uint8_t[pixelCount * 4];
        for (size_t i = 0; i < pixelCount; i++) {
            rgba[i*4+0] = pixelData[i*3+0];
            rgba[i*4+1] = pixelData[i*3+1];
            rgba[i*4+2] = pixelData[i*3+2];
            rgba[i*4+3] = 255;
        }
        [tex replaceRegion:MTLRegionMake2D(0, 0, width, height) mipmapLevel:0 withBytes:rgba bytesPerRow:width * 4];
        delete[] rgba;
        [dbg appendString:@"  ✓ 24-bit\n"];
    } else if (rgbBitCount == 16) {
        // Use masks to figure out the format
        auto calcShift = [](uint32_t mask) -> int {
            if (mask == 0) return 0;
            int shift = 0;
            while ((mask & 1) == 0) { mask >>= 1; shift++; }
            return shift;
        };
        auto calcBits = [](uint32_t mask) -> int {
            int bits = 0;
            while (mask) { bits += (mask & 1); mask >>= 1; }
            return bits;
        };
        
        int rShift = calcShift(rMask), rBits = calcBits(rMask);
        int gShift = calcShift(gMask), gBits = calcBits(gMask);
        int bShift = calcShift(bMask), bBits = calcBits(bMask);
        int aShift = calcShift(aMask), aBits = calcBits(aMask);
        
        [dbg appendFormat:@"  R=%d/%d G=%d/%d B=%d/%d A=%d/%d\n",
         rShift, rBits, gShift, gBits, bShift, bBits, aShift, aBits];
        
        size_t pixelCount = width * height;
        uint8_t *rgba = new uint8_t[pixelCount * 4];
        for (size_t i = 0; i < pixelCount; i++) {
            uint16_t px = pixelData[i*2] | (pixelData[i*2+1] << 8);
            uint8_t r = 0, g = 0, b = 0, a = 255;
            if (rBits > 0) { uint32_t v = (px >> rShift) & ((1 << rBits) - 1); r = (v * 255) / ((1 << rBits) - 1); }
            if (gBits > 0) { uint32_t v = (px >> gShift) & ((1 << gBits) - 1); g = (v * 255) / ((1 << gBits) - 1); }
            if (bBits > 0) { uint32_t v = (px >> bShift) & ((1 << bBits) - 1); b = (v * 255) / ((1 << bBits) - 1); }
            if (aBits > 0) { uint32_t v = (px >> aShift) & ((1 << aBits) - 1); a = (v * 255) / ((1 << aBits) - 1); }
            rgba[i*4+0] = b;
            rgba[i*4+1] = g;
            rgba[i*4+2] = r;
            rgba[i*4+3] = a;
        }
        [tex replaceRegion:MTLRegionMake2D(0, 0, width, height) mipmapLevel:0 withBytes:rgba bytesPerRow:width * 4];
        delete[] rgba;
        [dbg appendString:@"  ✓ 16-bit\n"];
    } else {
        [dbg appendFormat:@"  Unsupported bits=%u\n", rgbBitCount];
        return nil;
    }
    
    return tex;
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
    
    // ===== Texture loading =====
    NSMutableString *dbg = [NSMutableString string];
    _texture = nil;
    
    NSString *texBasename = @"weihnachtsman"; // default Santa
    if (mesh.textureName && mesh.textureName.length > 0) {
        NSString *ref = [mesh.textureName stringByReplacingOccurrencesOfString:@"\\" withString:@"/"];
        NSString *filename = [ref lastPathComponent];
        if (filename.length > 0) {
            texBasename = [filename stringByDeletingPathExtension];
        }
    }
    [dbg appendFormat:@"Texture basename: %@\n", texBasename];
    
    // 1. Direct name try karein
    NSString *ddsPath = [NSString stringWithFormat:@"maps\\%@.dds", texBasename];
    _texture = [self loadDDSTextureNamed:ddsPath debugOut:dbg];
    
    // 2. Common Santa textures fallback
    if (!_texture) {
        NSArray *fallbacks = @[
            @"maps\\weihnachtsman.dds",
            @"maps\\weihnachtsman1.dds",
            @"maps\\santa.dds",
            @"maps\\schneemann.dds",
        ];
        for (NSString *p in fallbacks) {
            _texture = [self loadDDSTextureNamed:p debugOut:dbg];
            if (_texture) {
                [dbg appendFormat:@"Fallback: %@\n", p];
                break;
            }
        }
    }
    
    // 3. Agar X-File mein .tga reference hai, TGA try karein
    if (!_texture) {
        NSString *tgaPath = [NSString stringWithFormat:@"maps\\%@.tga", texBasename];
        _texture = [self loadTGATextureNamed:tgaPath];
        if (_texture) [dbg appendString:@"TGA loaded\n"];
    }
    
    // 4. Last resort — white
    if (!_texture) {
        [dbg appendString:@"→ White fallback\n"];
        _texture = [self whiteTexture];
    }
    
    self.textureDebugInfo = dbg;
    NSLog(@"[Texture] %@", dbg);
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
