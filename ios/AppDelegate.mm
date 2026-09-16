#import "AppDelegate.h"
#import "GameEngine.h"

@implementation AppDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    self.window = [[UIWindow alloc] initWithFrame:[[UIScreen mainScreen] bounds]];
    
    UIViewController *viewController = [[UIViewController alloc] init];
    viewController.view.backgroundColor = [UIColor colorWithRed:0.1 green:0.1 blue:0.2 alpha:1.0];
    
    UILabel *label = [[UILabel alloc] initWithFrame:viewController.view.bounds];
    label.text = @"Santa iOS Engine\nLoading XPK...";
    label.numberOfLines = 0;
    label.textColor = [UIColor whiteColor];
    label.textAlignment = NSTextAlignmentCenter;
    label.font = [UIFont boldSystemFontOfSize:24];
    [viewController.view addSubview:label];
    
    self.window.rootViewController = viewController;
    [self.window makeKeyAndVisible];
    
    // Engine start karein
    [GameEngine startEngine];
    
    return YES;
}

@end
