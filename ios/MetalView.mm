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
        _textureDebugInfo = @"(loading)";
        _commandQueue = [_device newCommandQueue];
        
        MTLSamplerDescriptor *sd = [[MTLSamplerDescriptor alloc] init];
        sd.minFilter = MTLSamplerMinMagFilterLinear;
        sd.magFilter = MTLSamplerMinMagFilterLinear;
        sd.sAddressMode = MTLSamplerAddressModeClampToEdge;
        sd.tAddressMode = MTLSamplerAddressModeClampToEdge;
        _sampler = [_device newSamplerStateWithDescriptor:sd];
        
        MTLDepthStencilDescriptor *dd = [[MTLDepthStencilDescriptor alloc] init];
        dd.depthCompareFunction = MTLCompareFunctionLess;
        dd.depthWriteEnabled = YES;
        _depthState = [_device newDepthStencilStateWithDescriptor:dd];
        
        id<MTLLibrary> lib = [_device newDefaultLibrary];
        id<MTLFunction> vf = [lib newFunctionWithName:@"mesh_vertex"];
        id<MTLFunction> ff = [lib newFunctionWithName:@"mesh_fragment"];
        
        MTLRenderPipelineDescriptor *pd = [[MTLRenderPipelineDescriptor alloc] init];
        pd.vertexFunction = vf;
        pd.fragmentFunction = ff;
        pd.colorAttachments[0].pixelFormat = self.colorPixelFormat;
        pd.depthAttachmentPixelFormat = self.depthStencilPixelFormat;
        
        NSError *err = nil;
        _meshPipelineState = [_device newRenderPipelineStateWithDescriptor:pd error:&err];
    }
    return self;
}

- (id<MTLTexture>)whiteTexture {
    MTLTextureDescriptor *d = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatBGRA8Unorm width:1 height:1 mipmapped:NO];
    d.usage = MTLTextureUsageShaderRead;
    id<MTLTexture> t = [_device newTextureWithDescriptor:d];
    uint8_t w[4] = {255,255,255,255};
    [t replaceRegion:MTLRegionMake2D(0,0,1,1) mipmapLevel:0 withBytes:w bytesPerRow:4];
    return t;
}

- (void)setMeshToRender:(MeshData *)mesh {
    if (!mesh || mesh.vertexCount <= 0 || mesh.faceCount <= 0) return;
    
    const float *verts = (const float *)mesh.vertices.bytes;
    const float *uvs = mesh.uvs ? (const float *)mesh.uvs.bytes : NULL;
    const uint32_t *faces = (const uint32_t *)mesh.indices.bytes;
    
    float minX = 1e9, maxX = -1e9, minY = 1e9, maxY = -1e9, minZ = 1e9, maxZ = -1e9;
    for (int i = 0; i < mesh.vertexCount; i++) {
        float x = verts[i*3], y = verts[i*3+1], z = verts[i*3+2];
        if (x<minX) minX=x; if (x>maxX) maxX=x;
        if (y<minY) minY=y; if (y>maxY) maxY=y;
        if (z<minZ) minZ=z; if (z>maxZ) maxZ=z;
    }
    float cx=(minX+maxX)/2, cy=(minY+maxY)/2, cz=(minZ+maxZ)/2;
    float maxDim = fmaxf(maxX-minX, fmaxf(maxY-minY, maxZ-minZ));
    if (maxDim < 0.001f) return;
    float s = 1.4f / maxDim;
    
    float *vb = new float[mesh.vertexCount * 5];
    for (int i = 0; i < mesh.vertexCount; i++) {
        vb[i*5+0] = (verts[i*3+0]-cx)*s;
        vb[i*5+1] = (verts[i*3+1]-cy)*s;
        vb[i*5+2] = (verts[i*3+2]-cz)*s;
        vb[i*5+3] = uvs ? uvs[i*2+0] : 0.5f;
        vb[i*5+4] = uvs ? (1.0f - uvs[i*2+1]) : 0.5f;
    }
    _vertexBuffer = [_device newBufferWithBytes:vb length:mesh.vertexCount*5*sizeof(float) options:MTLResourceStorageModeShared];
    delete[] vb;
    
    _indexBuffer = [_device newBufferWithBytes:faces length:mesh.faceCount*3*sizeof(uint32_t) options:MTLResourceStorageModeShared];
    _indexCount = mesh.faceCount * 3;
    
    _texture = [self whiteTexture];
    self.textureDebugInfo = [NSString stringWithFormat:@"@%lu: %d v, %d f",
                             (unsigned long)mesh.offset, mesh.vertexCount, mesh.faceCount];
}

- (void)mtkView:(MTKView *)v drawableSizeWillChange:(CGSize)s {}

- (void)drawInMTKView:(MTKView *)view {
    if (!_meshPipelineState || _indexCount <= 0) return;
    if (!_vertexBuffer || !_indexBuffer) return;
    
    CGSize ds = view.drawableSize;
    if (ds.width <= 0 || ds.height <= 0) return;
    
    if (!_depthTexture || !CGSizeEqualToSize(_lastDrawableSize, ds)) {
        MTLTextureDescriptor *d = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatDepth32Float width:ds.width height:ds.height mipmapped:NO];
        d.usage = MTLTextureUsageRenderTarget;
        d.storageMode = MTLStorageModePrivate;
        _depthTexture = [_device newTextureWithDescriptor:d];
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
    
    id<MTLCommandBuffer> cb = [_commandQueue commandBuffer];
    id<MTLRenderCommandEncoder> e = [cb renderCommandEncoderWithDescriptor:rpd];
    [e setRenderPipelineState:_meshPipelineState];
    [e setDepthStencilState:_depthState];
    [e setVertexBuffer:_vertexBuffer offset:0 atIndex:0];
    [e setVertexBytes:&_angle length:sizeof(float) atIndex:1];
    [e setFragmentTexture:_texture atIndex:0];
    [e setFragmentSamplerState:_sampler atIndex:0];
    [e drawIndexedPrimitives:MTLPrimitiveTypeTriangle indexCount:_indexCount indexType:MTLIndexTypeUInt32 indexBuffer:_indexBuffer indexBufferOffset:0];
    [e endEncoding];
    [cb presentDrawable:view.currentDrawable];
    [cb commit];
}

@end
