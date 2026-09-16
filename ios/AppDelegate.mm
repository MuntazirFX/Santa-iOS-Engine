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
    textView.font = [UIFont fontWithName:@"Courier" size:10];
    textView.editable = NO;
    [viewController.view addSubview:textView];
    
    NSMutableString *log = [NSMutableString string];
    [log appendString:@"=== Mesh scan of all X-Files ===\n\n"];
    
    // Saare offsets jo XPK scan se mile
    NSArray *offsets = @[
        @21047, @23006, @24801, @30231, @32146,
        @33915, @35939, @38063, @41046, @42940,
        @44576, @46942, @49451, @51810, @113582,
        @116079, @118804, @120937, @123085, @126362,
        @128111, @130435, @131615, @135241, @137486
    ];
    
    for (NSNumber *off in offsets) {
        @autoreleasepool {
            MeshData *mesh = [GameEngine extractMeshAtOffset:[off unsignedIntegerValue]];
            if (mesh && mesh.vertexCount > 0) {
                NSString *tex = mesh.textureName ? [mesh.textureName lastPathComponent] : @"(none)";
                [log appendFormat:@"@%@: %d v, %d f, %@\n",
                 off, mesh.vertexCount, mesh.faceCount, tex];
            } else {
                [log appendFormat:@"@%@: FAILED\n", off];
            }
        }
    }
    
    textView.text = log;
    
    self.window.rootViewController = viewController;
    [self.window makeKeyAndVisible];
    
    return YES;
}

@end
