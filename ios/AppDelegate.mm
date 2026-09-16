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
    
    NSMutableString *output = [NSMutableString string];
    
    // STEP 1: fire.txt load karke verify karein
    NSData *fireData = [GameEngine loadAssetNamed:@"effects\\fire.txt"];
    if (fireData && fireData.length > 0) {
        [output appendFormat:@"fire.txt loaded: %lu bytes\n", (unsigned long)fireData.length];
        const uint8_t *fb = (const uint8_t *)fireData.bytes;
        [output appendString:@"First 64 ASCII:\n"];
        for (int i = 0; i < 64 && i < fireData.length; i++) {
            char c = (char)fb[i];
            if (c >= 32 && c < 127) [output appendFormat:@"%c", c];
            else [output appendString:@"."];
        }
        [output appendString:@"\n\n"];
    } else {
        [output appendString:@"fire.txt FAILED to load!\n\n"];
    }
    
    // STEP 2: Poori XPK file mein 'xof ' (0x78 0x6f 0x66 0x20) dhoondein
    NSString *xpkPath = [[NSBundle mainBundle] pathForResource:@"xmas" ofType:@"xpk"];
    NSData *xpkData = [NSData dataWithContentsOfFile:xpkPath];
    
    if (xpkData && xpkData.length > 0) {
        [output appendFormat:@"XPK size: %lu bytes\n", (unsigned long)xpkData.length];
        [output appendString:@"Searching for 'xof ' signature...\n\n"];
        
        const uint8_t *bytes = (const uint8_t *)xpkData.bytes;
        int found = 0;
        for (NSUInteger i = 0; i < xpkData.length - 4; i++) {
            if (bytes[i] == 0x78 && bytes[i+1] == 0x6f && bytes[i+2] == 0x66 && bytes[i+3] == 0x20) {
                // Version bytes (next 4 bytes after "xof ")
                uint8_t v1 = bytes[i+4];
                uint8_t v2 = bytes[i+5];
                uint8_t v3 = bytes[i+6];
                uint8_t v4 = bytes[i+7];
                
                [output appendFormat:@"Found at %lu: xof %c%c%c%c\n", (unsigned long)i, v1, v2, v3, v4];
                found++;
                if (found >= 5) break;
            }
        }
        [output appendFormat:@"\nTotal: %d found", found];
    } else {
        [output appendString:@"XPK file not found!\n"];
    }
    
    textView.text = output;
    
    self.window.rootViewController = viewController;
    [self.window makeKeyAndVisible];
    
    return YES;
}

@end
