#import "MetalView.h"
#import "GameEngine.h"

#import <Metal/Metal.h>
#import <MetalKit/MetalKit.h>


@implementation MetalView
{
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


// ============================================================
// Init
// ============================================================

- (instancetype)initWithFrame:(CGRect)frame
{
    _device =
        MTLCreateSystemDefaultDevice();


    self =
        [super initWithFrame:frame
                      device:_device];


    if (self)
    {
        self.clearColor =
            MTLClearColorMake(
                0.05,
                0.05,
                0.15,
                1.0
            );


        self.colorPixelFormat =
            MTLPixelFormatBGRA8Unorm;


        self.depthStencilPixelFormat =
            MTLPixelFormatDepth32Float;


        self.preferredFramesPerSecond =
            60;


        self.delegate =
            self;


        self.paused =
            NO;


        self.enableSetNeedsDisplay =
            NO;


        _frameCount = 0;

        _angle = 0.0f;

        _indexCount = 0;

        _lastDrawableSize =
            CGSizeZero;


        self.textureDebugInfo =
            @"Waiting for mesh";


        _commandQueue =
            [_device newCommandQueue];


        // ====================================================
        // Sampler
        // ====================================================

        MTLSamplerDescriptor *sd =
            [[MTLSamplerDescriptor alloc] init];


        sd.minFilter =
            MTLSamplerMinMagFilterLinear;


        sd.magFilter =
            MTLSamplerMinMagFilterLinear;


        sd.sAddressMode =
            MTLSamplerAddressModeClampToEdge;


        sd.tAddressMode =
            MTLSamplerAddressModeClampToEdge;


        _sampler =
            [_device
             newSamplerStateWithDescriptor:sd];


        // ====================================================
        // Depth
        // ====================================================

        MTLDepthStencilDescriptor *dd =
            [[MTLDepthStencilDescriptor alloc] init];


        dd.depthCompareFunction =
            MTLCompareFunctionLess;


        dd.depthWriteEnabled =
            YES;


        _depthState =
            [_device
             newDepthStencilStateWithDescriptor:dd];


        // ====================================================
        // Metal Library
        // ====================================================

        id<MTLLibrary> lib =
            [_device newDefaultLibrary];


        if (!lib)
        {
            NSLog(@"[Metal] ERROR: default library missing");
        }


        id<MTLFunction> vf =
            [lib newFunctionWithName:@"mesh_vertex"];


        id<MTLFunction> ff =
            [lib newFunctionWithName:@"mesh_fragment"];


        if (!vf)
        {
            NSLog(@"[Metal] ERROR: mesh_vertex missing");
        }


        if (!ff)
        {
            NSLog(@"[Metal] ERROR: mesh_fragment missing");
        }


        // ====================================================
        // Pipeline
        // ====================================================

        MTLRenderPipelineDescriptor *pd =
            [[MTLRenderPipelineDescriptor alloc] init];


        pd.vertexFunction =
            vf;


        pd.fragmentFunction =
            ff;


        pd.colorAttachments[0].pixelFormat =
            self.colorPixelFormat;


        pd.depthAttachmentPixelFormat =
            self.depthStencilPixelFormat;


        NSError *error = nil;


        _meshPipelineState =
            [_device
             newRenderPipelineStateWithDescriptor:pd
             error:&error];


        if (!_meshPipelineState)
        {
            NSLog(@"[Metal] Pipeline ERROR: %@",
                  error);
        }
        else
        {
            NSLog(@"[Metal] Pipeline OK");
        }
    }


    return self;
}


// ============================================================
// White texture
// ============================================================

- (id<MTLTexture>)whiteTexture
{
    MTLTextureDescriptor *d =
        [MTLTextureDescriptor
         texture2DDescriptorWithPixelFormat:
            MTLPixelFormatBGRA8Unorm
         width:1
         height:1
         mipmapped:NO];


    d.usage =
        MTLTextureUsageShaderRead;


    id<MTLTexture> t =
        [_device
         newTextureWithDescriptor:d];


    uint8_t pixel[4] =
    {
        255,
        255,
        255,
        255
    };


    [t replaceRegion:
        MTLRegionMake2D(
            0,
            0,
            1,
            1
        )
       mipmapLevel:0
         withBytes:pixel
       bytesPerRow:4];


    return t;
}


// ============================================================
// Set mesh
// ============================================================

- (void)setMeshToRender:(MeshData *)mesh
{
    if (!mesh)
    {
        NSLog(@"[Metal] setMeshToRender: mesh is nil");

        _indexCount = 0;

        return;
    }


    NSLog(@"[Metal] Mesh received");
    NSLog(@"[Metal] Vertices: %d",
          mesh.vertexCount);
    NSLog(@"[Metal] Faces: %d",
          mesh.faceCount);
    NSLog(@"[Metal] Debug: %@",
          mesh.debugInfo);


    if (mesh.vertexCount <= 0 ||
        mesh.faceCount <= 0)
    {
        NSLog(@"[Metal] Invalid mesh");

        _indexCount = 0;

        return;
    }


    const float *verts =
        (const float *)mesh.vertices.bytes;


    const float *colors =
        mesh.colors
        ? (const float *)mesh.colors.bytes
        : NULL;


    const uint32_t *faces =
        (const uint32_t *)mesh.indices.bytes;


    // ========================================================
    // Bounds
    // ========================================================

    float minX =  1e30f;
    float maxX = -1e30f;

    float minY =  1e30f;
    float maxY = -1e30f;

    float minZ =  1e30f;
    float maxZ = -1e30f;


    for (int i = 0;
         i < mesh.vertexCount;
         ++i)
    {
        float x =
            verts[i * 3 + 0];

        float y =
            verts[i * 3 + 1];

        float z =
            verts[i * 3 + 2];


        minX = fminf(minX, x);
        maxX = fmaxf(maxX, x);

        minY = fminf(minY, y);
        maxY = fmaxf(maxY, y);

        minZ = fminf(minZ, z);
        maxZ = fmaxf(maxZ, z);
    }


    float cx =
        (minX + maxX) * 0.5f;


    float cy =
        (minY + maxY) * 0.5f;


    float cz =
        (minZ + maxZ) * 0.5f;


    float maxDim =
        fmaxf(
            maxX - minX,
            fmaxf(
                maxY - minY,
                maxZ - minZ
            )
        );


    NSLog(@"[Metal] Bounds:");
    NSLog(@"X: %f -> %f",
          minX,
          maxX);
    NSLog(@"Y: %f -> %f",
          minY,
          maxY);
    NSLog(@"Z: %f -> %f",
          minZ,
          maxZ);


    if (maxDim < 0.0001f)
    {
        NSLog(@"[Metal] ERROR: mesh has zero size");

        _indexCount = 0;

        return;
    }


    float scale =
        1.4f / maxDim;


    // ========================================================
    // Vertex layout:
    //
    // X Y Z R G B
    //
    // 6 floats
    // ========================================================

    size_t vertexFloatCount =
        (size_t)mesh.vertexCount * 6;


    float *vb =
        new float[vertexFloatCount];


    for (int i = 0;
         i < mesh.vertexCount;
         ++i)
    {
        float x =
            (verts[i * 3 + 0] - cx)
            * scale;


        float y =
            (verts[i * 3 + 1] - cy)
            * scale;


        float z =
            (verts[i * 3 + 2] - cz)
            * scale;


        vb[i * 6 + 0] =
            x;


        vb[i * 6 + 1] =
            y;


        vb[i * 6 + 2] =
            z;


        if (colors)
        {
            vb[i * 6 + 3] =
                colors[i * 3 + 0];


            vb[i * 6 + 4] =
                colors[i * 3 + 1];


            vb[i * 6 + 5] =
                colors[i * 3 + 2];
        }
        else
        {
            vb[i * 6 + 3] =
                0.8f;


            vb[i * 6 + 4] =
                0.8f;


            vb[i * 6 + 5] =
                0.8f;
        }
    }


    _vertexBuffer =
        [_device
         newBufferWithBytes:vb
         length:vertexFloatCount *
                sizeof(float)
         options:MTLResourceStorageModeShared];


    delete[] vb;


    // ========================================================
    // Index buffer
    // ========================================================

    size_t indexByteCount =
        (size_t)mesh.faceCount *
        3 *
        sizeof(uint32_t);


    _indexBuffer =
        [_device
         newBufferWithBytes:faces
         length:indexByteCount
         options:MTLResourceStorageModeShared];


    _indexCount =
        mesh.faceCount * 3;


    // ========================================================
    // Texture
    // ========================================================

    _texture =
        [self whiteTexture];


    self.textureDebugInfo =
        [NSString stringWithFormat:
            @"Mesh OK: %d vertices / %d faces",
            mesh.vertexCount,
            mesh.faceCount];


    NSLog(@"[Metal] Render mesh ready");
    NSLog(@"[Metal] Index count: %d",
          _indexCount);
}


// ============================================================
// Drawable resize
// ============================================================

- (void)mtkView:(MTKView *)view
drawableSizeWillChange:(CGSize)size
{
    _lastDrawableSize =
        CGSizeZero;
}


// ============================================================
// Draw
// ============================================================

- (void)drawInMTKView:(MTKView *)view
{
    if (!_meshPipelineState)
        return;


    if (!_vertexBuffer ||
        !_indexBuffer ||
        _indexCount <= 0)
    {
        return;
    }


    CGSize drawableSize =
        view.drawableSize;


    if (drawableSize.width <= 0 ||
        drawableSize.height <= 0)
    {
        return;
    }


    // ========================================================
    // Depth texture
    // ========================================================

    if (!_depthTexture ||
        !CGSizeEqualToSize(
            _lastDrawableSize,
            drawableSize
        ))
    {
        MTLTextureDescriptor *d =
            [MTLTextureDescriptor
             texture2DDescriptorWithPixelFormat:
                MTLPixelFormatDepth32Float
             width:(NSUInteger)drawableSize.width
             height:(NSUInteger)drawableSize.height
             mipmapped:NO];


        d.usage =
            MTLTextureUsageRenderTarget;


        d.storageMode =
            MTLStorageModePrivate;


        _depthTexture =
            [_device
             newTextureWithDescriptor:d];


        _lastDrawableSize =
            drawableSize;
    }


    // ========================================================
    // Animation
    // ========================================================

    _frameCount++;

    _angle += 0.01f;


    if (_angle > 6.2831853f)
        _angle -= 6.2831853f;


    // ========================================================
    // Render pass
    // ========================================================

    MTLRenderPassDescriptor *rpd =
        view.currentRenderPassDescriptor;


    if (!rpd)
        return;


    rpd.depthAttachment.texture =
        _depthTexture;


    rpd.depthAttachment.clearDepth =
        1.0;


    rpd.depthAttachment.loadAction =
        MTLLoadActionClear;


    rpd.depthAttachment.storeAction =
        MTLStoreActionDontCare;


    // ========================================================
    // Command buffer
    // ========================================================

    id<MTLCommandBuffer> cb =
        [_commandQueue commandBuffer];


    id<MTLRenderCommandEncoder> encoder =
        [cb renderCommandEncoderWithDescriptor:rpd];


    [encoder
        setRenderPipelineState:
            _meshPipelineState];


    [encoder
        setDepthStencilState:
            _depthState];


    [encoder
        setVertexBuffer:
            _vertexBuffer
        offset:0
        atIndex:0];


    [encoder
        setVertexBytes:
            &_angle
        length:sizeof(float)
        atIndex:1];


    if (_texture)
    {
        [encoder
            setFragmentTexture:
                _texture
            atIndex:0];


        [encoder
            setFragmentSamplerState:
                _sampler
            atIndex:0];
    }


    [encoder
        drawIndexedPrimitives:
            MTLPrimitiveTypeTriangle
        indexCount:_indexCount
        indexType:MTLIndexTypeUInt32
        indexBuffer:_indexBuffer
        indexBufferOffset:0];


    [encoder endEncoding];


    id<CAMetalDrawable> drawable =
        view.currentDrawable;


    if (drawable)
    {
        [cb presentDrawable:drawable];
    }


    [cb commit];
}


@end
