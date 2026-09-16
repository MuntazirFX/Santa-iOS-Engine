#import <UIKit/UIKit.h>
#import <MetalKit/MetalKit.h>

@interface MetalView : MTKView <MTKViewDelegate>
- (instancetype)initWithFrame:(CGRect)frame;
@end
