#import "AppDelegate.h"
#import "GameEngine.h"

@implementation AppDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    self.window = [[UIWindow alloc] initWithFrame:[[UIScreen mainScreen] bounds]];
    
    UIViewController *viewController = [[UIViewController alloc] init];
    viewController.view.backgroundColor = [UIColor blackColor];
    
    // Screen par logs dikhane ke liye TextView
    UITextView *textView = [[UITextView alloc] initWithFrame:viewController.view.bounds];
    textView.backgroundColor = [UIColor blackColor];
    textView.textColor = [UIColor greenColor];
    textView.font = [UIFont fontWithName:@"Courier" size:11];
    textView.editable = NO;
    [viewController.view addSubview:textView];
    
    // .x file load karke hex dump screen par dikhayein
    NSMutableString *output = [NSMutableString string];
    NSData *xData = [GameEngine loadAssetNamed:@"gfx\\schneemann_000.x"];
    
    if (xData && xData.length > 0) {
        [output appendFormat:@"File size: %lu bytes\n\n", (unsigned long)xData.length];
        
        const uint8_t *bytes = (const uint8_t *)xData.bytes;
        [output appendString:@"First 128 bytes (Hex):\n"];
        for (int i = 0; i < 128 && i < xData.length; i++) {
            [output appendFormat:@"%02x ", bytes[i]];
            if ((i + 1) % 16 == 0) [output appendString:@"\n"];
        }
        
        [output appendString:@"\nASCII:\n"];
        for (int i = 0; i < 128 && i < xData.length; i++) {
            char c = (char)bytes[i];
            if (c >= 32 && c < 127) {
                [output appendFormat:@"%c", c];
            } else {
                [output appendString:@"."];
            }
        }
    } else {
        [output appendString:@"Failed to load .x file!\nCheck Console/Logs."];
    }
    
    textView.text = output;
    
    self.window.rootViewController = viewController;
    [self.window makeKeyAndVisible];
    
    return YES;
}

@end
