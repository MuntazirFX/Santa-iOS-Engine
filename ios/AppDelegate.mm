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
    
    // Status label (small, top)
    UITextView *logView = [[UITextView alloc] initWithFrame:CGRectMake(0, 40, viewController.view.bounds.size.width, 90)];
    logView.backgroundColor = [UIColor colorWithWhite:0.0 alpha:0.6];
    logView.textColor = [UIColor greenColor];
    logView.font = [UIFont fontWithName:@"Courier" size:10];
    logView.editable = NO;
    logView.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    [viewController.view addSubview:logView];
    
    NSMutableString *log = [NSMutableString string];
    
    MeshData *mesh = [GameEngine extractFirstMeshAtOffset:21047];
    if (mesh && mesh.vertexCount > 0 && mesh.faceCount > 0) {
        [log appendFormat:@"Mesh: %d verts, %d faces\n", mesh.vertexCount, mesh.faceCount];
        [log appendFormat:@"UVs: %@\n", mesh.uvs ? @"yes" : @"no"];
        [log appendFormat:@"Tex: %@\n", mesh.textureName ? [mesh.textureName lastPathComponent] : @"(none)"];
        [metalView setMeshToRender:mesh];
    } else {
        [log appendString:@"Mesh extraction failed\n"];
    }
    
    logView.text = log;
    
    self.window.rootViewController = viewController;
    [self.window makeKeyAndVisible];
    
    return YES;
}

@end
