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
    
    // Debug output overlay
    UITextView *logView = [[UITextView alloc] initWithFrame:CGRectMake(0, 40, viewController.view.bounds.size.width, 280)];
    logView.backgroundColor = [UIColor colorWithWhite:0.0 alpha:0.75];
    logView.textColor = [UIColor greenColor];
    logView.font = [UIFont fontWithName:@"Courier" size:9];
    logView.editable = NO;
    logView.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    [viewController.view addSubview:logView];
    
    NSMutableString *log = [NSMutableString string];
    
    MeshData *mesh = [GameEngine extractFirstMeshAtOffset:21047];
    if (mesh && mesh.vertexCount > 0 && mesh.faceCount > 0) {
        [log appendFormat:@"Mesh: %d verts, %d faces\n\n", mesh.vertexCount, mesh.faceCount];
        [metalView setMeshToRender:mesh];
        [log appendString:metalView.textureDebugInfo];
    } else {
        [log appendString:@"Mesh extraction failed\n"];
    }
    
    logView.text = log;
    
    self.window.rootViewController = viewController;
    [self.window makeKeyAndVisible];
    
    return YES;
}

@end
