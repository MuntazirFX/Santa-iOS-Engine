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

- (id<MTLTexture>)loadDDSTextureNamed:(NSString *)name debugOut:(NSMutableString *)dbg {
    NSData *ddsData = [GameEngine loadAssetNamed:name];
    if (!ddsData) {
        [dbg appendFormat:@"DDS %@: NOT FOUND\n", name];
        return nil;
    }
    
    [dbg appendFormat:@"DDS %@: %lu bytes\n", name, (unsigned long)ddsData.length];
    
    if (ddsData.length < 128) {
        [dbg appendString:@"  Too small\n"];
        return nil;
    }
    
    const uint8_t *bytes = (const uint8_t *)ddsData.bytes;
    
    if (bytes[0] != 'D' || bytes[1] != 'D' || bytes[2] != 'S' || bytes[3] != ' ') {
        [dbg appendString:@"  Bad magic\n"];
        return nil;
    }
    
    uint32_t height = *(uint32_t *)(bytes + 12);
    uint32_t width = *(uint32_t *)(bytes + 16);
    uint32_t mipCount = *(uint32_t *)(bytes + 28);
    uint32_t pfFlags = *(uint32_t *)(bytes + 80);
    uint32_t fourCC = *(uint32_t *)(bytes + 84);
    uint32_t rgbBitCount = *(uint32_t *)(bytes + 88);
    uint32_t rMask = *(uint32_t *)(bytes + 92);
    uint32_t gMask = *(uint32_t *)(bytes + 96);
    uint32_t bMask = *(uint32_t *)(bytes + 100);
    uint32_t aMask = *(uint32_t *)(bytes + 104);
    
    [dbg appendFormat:@"  %ux%u mips=%u fourCC=0x%x bits=%u\n", width, height, mipCount, fourCC, rgbBitCount];
    [dbg appendFormat:@"  R=%x G=%x B=%x A=%x\n", rMask, gMask, bMask, aMask];
    
    if (fourCC != 0) {
        [dbg appendString:@"  COMPRESSED (DXT) — skipping\n"];
        return nil;
    }
    
    if (width == 0 || height == 0 || width > 4096 || height > 4096) {
        [dbg appendString:@"  Bad dims\n"];
        return nil;
    }
    
    MTLTextureDescriptor *texDesc = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatBGRA8Unorm width:width height:height mipmapped:NO];
    texDesc.usage = MTLTextureUsageShaderRead;
    id<MTLTexture> tex = [_device newTextureWithDescriptor:texDesc];
    if (!tex) {
        [dbg appendString:@"  MTLTexture fail\n"];
        return nil;
    }
    
    const uint8_t *pixelData = bytes + 128;
    
    [dbg appendString:@"  px[0..11]: "];
    for (int i = 0; i < 12; i++) [dbg appendFormat:@"%02x ", pixelData[i]];
    [dbg appendString:@"\n"];
    
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
        // 16-bit: use masks to determine channel positions
        // Common: 5-6-5 (R5G6B5) or 4-4-4-4 (ARGB4444) or 1-5-5-5 (A1R5G5B5)
        int rShift = 0, gShift = 0, bShift = 0, aShift = 0;
        int rBits = 0, gBits = 0, bBits = 0, aBits = 0;
        
        // Find lowest set bit = shift, count set bits = bit count
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
        
        rShift = calcShift(rMask); rBits = calcBits(rMask);
        gShift = calcShift(gMask); gBits = calcBits(gMask);
        bShift = calcShift(bMask); bBits = calcBits(bMask);
        aShift = calcShift(aMask); aBits = calcBits(aMask);
        
        [dbg appendFormat:@"  shifts R=%d G=%d B=%d A=%d bits R=%d G=%d B=%d A=%d\n",
         rShift, gShift, bShift, aShift, rBits, gBits, bBits, aBits];
        
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
        [dbg appendString:@"  ✓ 16-bit (with masks)\n"];
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
    
    NSMutableString *dbg = [NSMutableString string];
    _texture = nil;
    
    NSString *basename = @"haus2";
    if (mesh.textureName && mesh.textureName.length > 0) {
        // Windows path fix: backslash ko forward slash mein badlein
        NSString *ref = [mesh.textureName stringByReplacingOccurrencesOfString:@"\\" withString:@"/"];
        NSString *filename = [ref lastPathComponent];
        if (filename.length > 0) {
            basename = [filename stringByDeletingPathExtension];
        }
    }
    [dbg appendFormat:@"basename: %@\n", basename];
    
    // DDS offsets jo humne XPK scan se dhoonde the (uncompressed, valid dims)
    NSArray *ddsOffsets = @[
        @1578864,  // 128x128 16-bit
        @5659034,  // 256x256 16-bit
        @5833924,  // 256x256 16-bit
        @6030704,  // 256x256 16-bit
        @6467782,  // 256x256 16-bit
        @4419012,  // 512x512 16-bit
        @5118190,  // 512x512 16-bit
        @8253169,  // 512x512 16-bit
        @8777585,  // 512x512 16-bit
        @9476763,  // 512x512 16-bit
    ];
    
    for (NSNumber *off in ddsOffsets) {
        NSData *ddsData = [GameEngine loadDDSAtOffset:[off unsignedIntegerValue]];
        if (!ddsData) continue;
        
        const uint8_t *b = (const uint8_t *)ddsData.bytes;
        if (b[0] != 'D' || b[1] != 'D' || b[2] != 'S' || b[3] != ' ') continue;
        
        uint32_t w = *(uint32_t *)(b + 16);
        uint32_t h = *(uint32_t *)(b + 12);
        [dbg appendFormat:@"Trying offset %@: %ux%u\n", off, w, h];
        
        // Manually create texture from this data
        id<MTLTexture> tex = [self createTextureFromDDSData:ddsData debug:dbg];
        if (tex) {
            _texture = tex;
            [dbg appendFormat:@"  ✓ Loaded via offset %@\n", off];
            break;
        }
    }
    
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
