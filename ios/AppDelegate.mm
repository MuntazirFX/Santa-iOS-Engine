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
    
    [log appendString:@"=== X-Files in XPK ===\n\n"];
    [log appendString:[GameEngine scanXPKForXFiles]];
    [log appendString:@"\n"];
    [log appendString:@"=== weihnachts files ===\n"];
    [log appendString:[GameEngine listAssetsByKeyword:@"weihnachts"]];
    
    textView.text = log;
    
    self.window.rootViewController = viewController;
    [self.window makeKeyAndVisible];
    
    return YES;
}

@end
