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
    
    UITextView *tv = [[UITextView alloc] initWithFrame:CGRectMake(0, 40, vc.view.bounds.size.width, 200)];
    tv.backgroundColor = [UIColor colorWithWhite:0.0 alpha:0.85];
    tv.textColor = [UIColor greenColor];
    tv.font = [UIFont fontWithName:@"Courier" size:9];
    tv.editable = NO;
    tv.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    [vc.view addSubview:tv];
    
    NSMutableString *log = [NSMutableString string];
    
    // ===== Load SANTA (correct file) =====
    [log appendString:@"Loading Santa...\n"];
    MeshData *mesh = [GameEngine extractMeshFromAsset:@"gfx\\weihnachtsman_000.x"];
    
    if (mesh && mesh.vertexCount > 0) {
        [log appendFormat:@"✅ SANTA LOADED\n%@\n", mesh.debugInfo ?: @""];
        [mv setMeshToRender:mesh];
    } else {
        [log appendString:@"❌ Santa load failed\n"];
    }
    
    // ===== List levels =====
    [log appendString:@"\nLevels:\n"];
    [log appendString:[GameEngine listLevelFiles]];
    
    tv.text = log;
    
    self.window.rootViewController = vc;
    [self.window makeKeyAndVisible];
    return YES;
}

@end
