#import <UIKit/UIKit.h>
#import <MetalKit/MetalKit.h>

@class MeshData;

@interface MetalView : MTKView <MTKViewDelegate>
- (instancetype)initWithFrame:(CGRect)frame;
- (void)setMeshToRender:(MeshData *)mesh;
- (id<MTLTexture>)loadDDSTextureNamed:(NSString *)name debugOut:(NSMutableString *)dbg;
@property (strong, nonatomic) NSString *textureDebugInfo;
@end
