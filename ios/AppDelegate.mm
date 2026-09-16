#import "AppDelegate.h"
#import "GameEngine.h"
#import "MetalView.h"

@implementation AppDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    self.window = [[UIWindow alloc] initWithFrame:[[UIScreen mainScreen] bounds]];
    
    UIViewController *viewController = [[UIViewController alloc] init];
    viewController.view.backgroundColor = [UIColor blackColor];
    
    MetalView *metalView = [[MetalView alloc] initWithFrame:viewController.view.bounds];
    metalView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [viewController.view addSubview:metalView];
    
    // Extract mesh and send to Metal view
    MeshData *mesh = [GameEngine extractFirstMeshAtOffset:21047];
    if (mesh) {
        [metalView setMeshToRender:mesh];
        NSLog(@"[AppDelegate] Mesh sent: %d verts, %d faces", mesh.vertexCount, mesh.faceCount);
    }
    
    self.window.rootViewController = viewController;
    [self.window makeKeyAndVisible];
    
    return YES;
}

@end
