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
    
    // LARGE text view to show bbox info
    UITextView *tv = [[UITextView alloc] initWithFrame:CGRectMake(0, 40, vc.view.bounds.size.width, 250)];
    tv.backgroundColor = [UIColor colorWithWhite:0.0 alpha:0.85];
    tv.textColor = [UIColor greenColor];
    tv.font = [UIFont fontWithName:@"Courier" size:9];
    tv.editable = NO;
    tv.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    [vc.view addSubview:tv];
    
    MeshData *mesh = [GameEngine extractSantaWithTransforms:960968];
    
    if (mesh && mesh.vertexCount > 0) {
        tv.text = [NSString stringWithFormat:@"MESH BBOX REPORT\n%d v, %d f\n\n%@",
                   mesh.vertexCount, mesh.faceCount, mesh.debugInfo ?: @"(no debug)"];
        [mv setMeshToRender:mesh];
    } else {
        tv.text = @"Extraction failed";
    }
    
    self.window.rootViewController = vc;
    [self.window makeKeyAndVisible];
    return YES;
}

@end
