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
    textView.font = [UIFont fontWithName:@"Courier" size:9];
    textView.editable = NO;
    [viewController.view addSubview:textView];
    
    NSMutableString *log = [NSMutableString string];
    
    // DDS files with 'haus'
    [log appendString:@"=== 'haus' files ===\n"];
    [log appendString:[GameEngine listAssetsByKeyword:@"haus"]];
    [log appendString:@"\n"];
    
    // DDS files with 'dach'
    [log appendString:@"=== 'dach' files ===\n"];
    [log appendString:[GameEngine listAssetsByKeyword:@"dach"]];
    [log appendString:@"\n"];
    
    // All DDS files
    [log appendString:@"=== All .dds (first 40) ===\n"];
    [log appendString:[GameEngine listAssetsByKeyword:@".dds"]];
    [log appendString:@"\n"];
    
    // All TGA files
    [log appendString:@"=== All .tga (first 20) ===\n"];
    [log appendString:[GameEngine listAssetsByKeyword:@".tga"]];
    
    textView.text = log;
    
    self.window.rootViewController = viewController;
    [self.window makeKeyAndVisible];
    
    return YES;
}

@end
