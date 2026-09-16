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
    
    tv.text = @"Scanning for Santa (30 sec)...";
    
    self.window.rootViewController = vc;
    [self.window makeKeyAndVisible];
    
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{
        NSString *result = [GameEngine scanForSantaModel];
        dispatch_async(dispatch_get_main_queue(), ^{
            tv.text = result;
        });
    });
    
    return YES;
}

@end
