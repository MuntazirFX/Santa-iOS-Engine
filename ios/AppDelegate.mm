#import "AppDelegate.h"
#import "GameEngine.h"

@implementation AppDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    self.window = [[UIWindow alloc] initWithFrame:[[UIScreen mainScreen] bounds]];
    
    UIViewController *vc = [[UIViewController alloc] init];
    vc.view.backgroundColor = [UIColor blackColor];
    
    UITextView *tv = [[UITextView alloc] initWithFrame:vc.view.bounds];
    tv.backgroundColor = [UIColor blackColor];
    tv.textColor = [UIColor greenColor];
    tv.font = [UIFont fontWithName:@"Courier" size:9];
    tv.editable = NO;
    [vc.view addSubview:tv];
    
    NSMutableString *log = [NSMutableString string];
    [log appendString:@"=== Finding Santa (big meshes) ===\n\n"];
    [log appendString:[GameEngine findAllMeshes]];
    
    tv.text = log;
    
    self.window.rootViewController = vc;
    [self.window makeKeyAndVisible];
    return YES;
}

@end
