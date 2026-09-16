#import "AppDelegate.h"
#import "GameEngine.h"
#import "MetalView.h"

@implementation AppDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    self.window = [[UIWindow alloc] initWithFrame:[[UIScreen mainScreen] bounds]];
    
    UIViewController *vc = [[UIViewController alloc] init];
    vc.view.backgroundColor = [UIColor blackColor];
    
    MetalView *mv = [[MetalView alloc] initWithFrame:vc.view.bounds];
    mv.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [vc.view addSubview:mv];
    
    UITextView *tv = [[UITextView alloc] initWithFrame:CGRectMake(0, 40, vc.view.bounds.size.width, 100)];
    tv.backgroundColor = [UIColor colorWithWhite:0.0 alpha:0.7];
    tv.textColor = [UIColor greenColor];
    tv.font = [UIFont fontWithName:@"Courier" size:10];
    tv.editable = NO;
    tv.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    [vc.view addSubview:tv];
    
    NSMutableString *log = [NSMutableString string];
    
    // Try @171669 (704 verts, 869 faces) — likely a big model
    MeshData *mesh = [GameEngine extractMeshAtOffset:960968];
    
    if (mesh && mesh.vertexCount > 0 && mesh.faceCount > 0) {
        [log appendFormat:@"Model @960968\n"];
        [log appendFormat:@"%d verts, %d faces\n", mesh.vertexCount, mesh.faceCount];
        [log appendFormat:@"Tex: %@\n\n", mesh.textureName ?: @"(none)"];
        [mv setMeshToRender:mesh];
        [log appendString:mv.textureDebugInfo];
    } else {
        [log appendString:@"Extraction failed!\n"];
    }
    
    tv.text = log;
    
    self.window.rootViewController = vc;
    [self.window makeKeyAndVisible];
    return YES;
}

@end
