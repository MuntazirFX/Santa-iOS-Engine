#import "AppDelegate.h"
#import "GameEngine.h"

@implementation AppDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    self.window = [[UIWindow alloc] initWithFrame:[[UIScreen mainScreen] bounds]];
    
    UIViewController *viewController = [[UIViewController alloc] init];
    viewController.view.backgroundColor = [UIColor blackColor];
    
    UITextView *textView = [[UITextView alloc] initWithFrame:viewController.view.bounds];
    textView.backgroundColor = [UIColor blackColor];
    textView.textColor = [UIColor greenColor];
    textView.font = [UIFont fontWithName:@"Courier" size:11];
    textView.editable = NO;
    [viewController.view addSubview:textView];
    
    MeshData *mesh = [GameEngine extractFirstMeshAtOffset:21047];
    
    NSMutableString *out = [NSMutableString string];
    if (mesh) {
        [out appendFormat:@"✓ Mesh extracted!\n"];
        [out appendFormat:@"Vertices: %d\n", mesh.vertexCount];
        [out appendFormat:@"Faces: %d\n\n", mesh.faceCount];
        
        const float *v = (const float *)mesh.vertices.bytes;
        int show = mesh.vertexCount > 15 ? 15 : mesh.vertexCount;
        [out appendString:@"First vertices:\n"];
        for (int i = 0; i < show; i++) {
            [out appendFormat:@"v%d: (%.3f, %.3f, %.3f)\n", i, v[i*3], v[i*3+1], v[i*3+2]];
        }
    } else {
        [out appendString:@"Mesh extraction failed!\nCheck logs for details."];
    }
    
    textView.text = out;
    
    self.window.rootViewController = viewController;
    [self.window makeKeyAndVisible];
    
    return YES;
}

@end
