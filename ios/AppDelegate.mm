#import "AppDelegate.h"
#import "GameEngine.h"
#import "MetalView.h"

@implementation AppDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    self.window = [[UIWindow alloc] initWithFrame:[[UIScreen mainScreen] bounds]];
    
    UIViewController *vc = [[UIViewController alloc] init];
    vc.view.backgroundColor = [UIColor blackColor];
    
    // Loading label (Santa scan takes 10-20 sec)
    UILabel *loading = [[UILabel alloc] initWithFrame:vc.view.bounds];
    loading.text = @"Scanning for Santa...\n(This takes ~15 seconds)";
    loading.numberOfLines = 0;
    loading.textAlignment = NSTextAlignmentCenter;
    loading.textColor = [UIColor greenColor];
    loading.backgroundColor = [UIColor blackColor];
    loading.font = [UIFont fontWithName:@"Courier" size:14];
    [vc.view addSubview:loading];
    
    // Add Metal view behind
    MetalView *mv = [[MetalView alloc] initWithFrame:vc.view.bounds];
    mv.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [vc.view insertSubview:mv atIndex:0];
    
    self.window.rootViewController = vc;
    [self.window makeKeyAndVisible];
    
    // Do the scan on a background thread so UI doesn't freeze
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{
        MeshData *mesh = [GameEngine findSantaMesh];
        
        dispatch_async(dispatch_get_main_queue(), ^{
            if (mesh && mesh.vertexCount > 0 && mesh.faceCount > 0) {
                [loading removeFromSuperview];
                [mv setMeshToRender:mesh];
                NSLog(@"✅ Santa loaded: %d v, %d f", mesh.vertexCount, mesh.faceCount);
            } else {
                loading.text = @"Santa not found!\nCheck console for logs.";
            }
        });
    });
    
    return YES;
}

@end
