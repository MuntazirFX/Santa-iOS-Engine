#import "MetalView.h"
#import "GameEngine.h"
#import <Metal/Metal.h>

@implementation MetalView {
    id<MTLDevice> _device;
    id<MTLCommandQueue> _commandQueue;
    id<MTLRenderPipelineState> _pipelineState;      // textured quad
    id<MTLRenderPipelineState> _meshPipelineState;  // 3D wireframe
    id<MTLTexture> _texture;
    id<MTLSamplerState> _sampler;
    id<MTLBuffer> _meshBuffer;
    int _meshVertexCount;
    int _frameCount;
}

- (instancetype)initWithFrame:(CGRect)frame {
    _device = MTLCreateSystemDefaultDevice();
    self = [super initWithFrame:frame device:_device];
    if (self) {
        self.clearColor = MTLClearColorMake(0.05, 0.05, 0.1, 1.0);
        self.colorPixelFormat = MTLPixelFormatBGRA8Unorm;
        self.preferredFramesPerSecond = 60;
        self.delegate = self;
        self.paused = NO;
        self.enableSetNeedsDisplay = NO;
        
        _frameCount = 0;
        _meshVertexCount = 0;
        _commandQueue = [_device newCommandQueue];
        
        [self createTexture];
        
        MTLSamplerDescriptor *sampDesc = [[MTLSamplerDescriptor alloc] init];
        sampDesc.minFilter = MTLSamplerMinMagFilterNearest;
        sampDesc.magFilter = MTLSamplerMinMagFilterNearest;
        sampDesc.sAddressMode = MTLSamplerAddressModeClampToEdge;
        sampDesc.tAddressMode = MTLSamplerAddressModeClampToEdge;
        _sampler = [_device newSamplerStateWithDescriptor:sampDesc];
        
        id<MTLLibrary> library = [_device newDefaultLibrary];
        
        // Quad pipeline
        {
            id<MTLFunction> vf = [library newFunctionWithName:@"vertex_main"];
            id<MTLFunction> ff = [library newFunctionWithName:@"fragment_main"];
            MTLRenderPipelineDescriptor *desc = [[MTLRenderPipelineDescriptor alloc] init];
            desc.vertexFunction = vf;
            desc.fragmentFunction = ff;
            desc.colorAttachments[0].pixelFormat = self.colorPixelFormat;
            NSError *err = nil;
            _pipelineState = [_device newRenderPipelineStateWithDescriptor:desc error:&err];
        }
        
        // Mesh pipeline
        {
            id<MTLFunction> vf = [library newFunctionWithName:@"mesh_vertex"];
            id<MTLFunction> ff = [library newFunctionWithName:@"mesh_fragment"];
            MTLRenderPipelineDescriptor *desc = [[MTLRenderPipelineDescriptor alloc] init];
            desc.vertexFunction = vf;
            desc.fragmentFunction = ff;
            desc.colorAttachments[0].pixelFormat = self.colorPixelFormat;
            NSError *err = nil;
            _meshPipelineState = [_device newRenderPipelineStateWithDescriptor:desc error:&err];
            if (!_meshPipelineState) NSLog(@"[MetalView] Mesh pipeline failed: %@", err);
            else NSLog(@"[MetalView] Mesh pipeline ready!");
        }
    }
    return self;
}

- (void)createTexture {
    // Empty texture (we're only rendering mesh now)
    MTLTextureDescriptor *texDesc = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatBGRA8Unorm width:4 height:4 mipmapped:NO];
    texDesc.usage = MTLTextureUsageShaderRead;
    _texture = [_device newTextureWithDescriptor:texDesc];
}

- (void)setMeshToRender:(MeshData *)mesh {
    if (!mesh || mesh.vertexCount == 0) return;
    
    const float *verts = (const float *)mesh.vertices.bytes;
    const uint32_t *faces = (const uint32_t *)mesh.indices.bytes;
    
    // Find bounding box
    float minX = 1e9, maxX = -1e9, minY = 1e9, maxY = -1e9, minZ = 1e9, maxZ = -1e9;
    for (int i = 0; i < mesh.vertexCount; i++) {
        float x = verts[i*3], y = verts[i*3+1], z = verts[i*3+2];
        if (x < minX) minX = x; if (x > maxX) maxX = x;
        if (y < minY) minY = y; if (y > maxY) maxY = y;
        if (z < minZ) minZ = z; if (z > maxZ) maxZ = z;
    }
    
    float cx = (minX + maxX) / 2.0f;
    float cy = (minY + maxY) / 2.0f;
    float cz = (minZ + maxZ) / 2.0f;
    float maxDim = fmaxf(maxX - minX, fmaxf(maxY - minY, maxZ - minZ));
    float scale = 1.6f / maxDim;
    
    NSLog(@"[MetalView] Mesh bounds: %.1f,%.1f,%.1f to %.1f,%.1f,%.1f | scale=%.4f",
          minX, minY, minZ, maxX, maxY, maxZ, scale);
    
    // Wireframe colors — rainbow based on face index
    float colors[8][3] = {
        {1.0, 0.3, 0.3}, {0.3, 1.0, 0.3}, {0.3, 0.3, 1.0}, {1.0, 1.0, 0.3},
        {1.0, 0.3, 1.0}, {0.3, 1.0, 1.0}, {1.0, 0.6, 0.2}, {0.6, 0.2, 1.0}
    };
    
    // Each face = triangle = 3 edges = 6 vertices (position + RGBA)
    int lineVertCount = mesh.faceCount * 6;
    float *lineData = new float[lineVertCount * 7];
    
    int out = 0;
    for (int f = 0; f < mesh.faceCount; f++) {
        uint32_t i0 = faces[f*3], i1 = faces[f*3+1], i2 = faces[f*3+2];
        if (i0 >= mesh.vertexCount || i1 >= mesh.vertexCount || i2 >= mesh.vertexCount) continue;
        
        float *c = colors[f % 8];
        
        // Vertex positions normalized
        float p0[3] = {(verts[i0*3]-cx)*scale, (verts[i0*3+1]-cy)*scale, (verts[i0*3+2]-cz)*scale};
        float p1[3] = {(verts[i1*3]-cx)*scale, (verts[i1*3+1]-cy)*scale, (verts[i1*3+2]-cz)*scale};
        float p2[3] = {(verts[i2*3]-cx)*scale, (verts[i2*3+1]-cy)*scale, (verts[i2*3+2]-cz)*scale};
        
        // Edge 1: p0 → p1
        float *v = &lineData[out * 7];
        v[0]=p0[0]; v[1]=p0[1]; v[2]=p0[2]; v[3]=c[0]; v[4]=c[1]; v[5]=c[2]; v[6]=1.0;
        out++;
        v = &lineData[out * 7];
        v[0]=p1[0]; v[1]=p1[1]; v[2]=p1[2]; v[3]=c[0]; v[4]=c[1]; v[5]=c[2]; v[6]=1.0;
        out++;
        
        // Edge 2: p1 → p2
        v = &lineData[out * 7];
        v[0]=p1[0]; v[1]=p1[1]; v[2]=p1[2]; v[3]=c[0]; v[4]=c[1]; v[5]=c[2]; v[6]=1.0;
        out++;
        v = &lineData[out * 7];
        v[0]=p2[0]; v[1]=p2[1]; v[2]=p2[2]; v[3]=c[0]; v[4]=c[1]; v[5]=c[2]; v[6]=1.0;
        out++;
        
        // Edge 3: p2 → p0
        v = &lineData[out * 7];
        v[0]=p2[0]; v[1]=p2[1]; v[2]=p2[2]; v[3]=c[0]; v[4]=c[1]; v[5]=c[2]; v[6]=1.0;
        out++;
        v = &lineData[out * 7];
        v[0]=p0[0]; v[1]=p0[1]; v[2]=p0[2]; v[3]=c[0]; v[4]=c[1]; v[5]=c[2]; v[6]=1.0;
        out++;
    }
    
    _meshVertexCount = out;
    _meshBuffer = [_device newBufferWithBytes:lineData length:out * 7 * sizeof(float) options:MTLResourceStorageModeShared];
    delete[] lineData;
    
    NSLog(@"[MetalView] Mesh buffer created: %d vertices (lines)", _meshVertexCount);
}

- (void)mtkView:(MTKView *)view drawableSizeWillChange:(CGSize)size {}

- (void)drawInMTKView:(MTKView *)view {
    _frameCount++;
    if (_frameCount <= 3) NSLog(@"[MetalView] draw frame %d (mesh verts: %d)", _frameCount, _meshVertexCount);
    
    MTLRenderPassDescriptor *rpd = view.currentRenderPassDescriptor;
    if (!rpd) return;
    
    id<MTLCommandBuffer> cmdBuf = [_commandQueue commandBuffer];
    id<MTLRenderCommandEncoder> enc = [cmdBuf renderCommandEncoderWithDescriptor:rpd];
    
    if (_meshVertexCount > 0 && _meshPipelineState) {
        [enc setRenderPipelineState:_meshPipelineState];
        [enc setVertexBuffer:_meshBuffer offset:0 atIndex:0];
        [enc drawPrimitives:MTLPrimitiveTypeLine vertexStart:0 vertexCount:_meshVertexCount];
    }
    
    [enc endEncoding];
    [cmdBuf presentDrawable:view.currentDrawable];
    [cmdBuf commit];
}

@end
