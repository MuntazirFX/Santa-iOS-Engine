#import "AppDelegate.h"
#import "GameEngine.h"
#import "MetalView.h"

@implementation AppDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    self.window = [[UIWindow alloc] initWithFrame:[[UIScreen mainScreen] bounds]];
    
    NSString *engineStatus = [GameEngine startEngine];
    NSLog(@"[AppDelegate] %@", engineStatus);
    
    UIViewController *viewController = [[UIViewController alloc] init];
    viewController.view.backgroundColor = [UIColor blackColor];
    
    // AHEM FIX: UIScreen.mainScreen.bounds use karein, na ke viewController.view.bounds
    CGRect screenBounds = [[UIScreen mainScreen] bounds];
    NSLog(@"[AppDelegate] Screen bounds: %.0fx%.0f", screenBounds.size.width, screenBounds.size.height);
    
    MetalView *metalView = [[MetalView alloc] initWithFrame:screenBounds];
    metalView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [viewController.view addSubview:metalView];
    
// UILabel *label = [[UILabel alloc] initWithFrame:CGRectMake(0, 50, screenBounds.size.width, 100)];
// label.text = engineStatus;
// label.numberOfLines = 0;
// label.textColor = [UIColor whiteColor];
// label.textAlignment = NSTextAlignmentCenter;
// label.font = [UIFont systemFontOfSize:12];
// [viewController.view addSubview:label];
    
    self.window.rootViewController = viewController;
    [self.window makeKeyAndVisible];
    
    return YES;
}

@end
