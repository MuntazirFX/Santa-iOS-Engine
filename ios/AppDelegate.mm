#import "AppDelegate.h"
#import "GameEngine.h"
#import "MetalView.h"

@implementation AppDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    self.window = [[UIWindow alloc] initWithFrame:[[UIScreen mainScreen] bounds]];
    
    // Engine start karein
    NSString *engineStatus = [GameEngine startEngine];
    NSLog(@"%@", engineStatus);
    
    // Base view controller banayein
    UIViewController *viewController = [[UIViewController alloc] init];
    viewController.view.backgroundColor = [UIColor blackColor];
    
    // Metal view ko addSubview ke zariye add karein
    MetalView *metalView = [[MetalView alloc] initWithFrame:viewController.view.bounds];
    metalView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [viewController.view addSubview:metalView];
    
    // Status label upar add karein
    UILabel *label = [[UILabel alloc] initWithFrame:CGRectMake(0, 50, viewController.view.bounds.size.width, 100)];
    label.text = engineStatus;
    label.numberOfLines = 0;
    label.textColor = [UIColor whiteColor];
    label.textAlignment = NSTextAlignmentCenter;
    label.font = [UIFont systemFontOfSize:12];
    [viewController.view addSubview:label];
    
    self.window.rootViewController = viewController;
    [self.window makeKeyAndVisible];
    
    return YES;
}

@end
