#import "AppDelegate.h"
#import "GameEngine.h"
#import "MetalView.h"

@implementation AppDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    self.window = [[UIWindow alloc] initWithFrame:[[UIScreen mainScreen] bounds]];
    
    // Engine start karein
    NSString *engineStatus = [GameEngine startEngine];
    NSLog(@"%@", engineStatus);
    
    // Metal view banayein aur screen par dikhayein
    MetalView *metalView = [[MetalView alloc] initWithFrame:self.window.bounds];
    UIViewController *viewController = [[UIViewController alloc] init];
    viewController.view = metalView;
    
    // Status label upar add karein
    UILabel *label = [[UILabel alloc] initWithFrame:CGRectMake(0, 50, self.window.bounds.size.width, 100)];
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
