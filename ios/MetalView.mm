#import "MetalView.h"
#import <Metal/Metal.h>
#import <QuartzCore/CAMetalLayer.h>

@implementation MetalView

- (instancetype)initWithFrame:(CGRect)frame {
    id<MTLDevice> device = MTLCreateSystemDefaultDevice();
    self = [super initWithFrame:frame device:device];
    if (self) {
        self.clearColor = MTLClearColorMake(0.1, 0.1, 0.2, 1.0);
        self.colorPixelFormat = MTLPixelFormatBGRA8Unorm;
        self.preferredFramesPerSecond = 60;
        NSLog(@"[MetalView] Metal Device: %@", device.name);
    }
    return self;
}

@end
