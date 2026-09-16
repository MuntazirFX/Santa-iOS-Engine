#import "GameEngine.h"
#include "AssetManager.h"
#include <string>
#include <vector>

@implementation GameEngine

+ (NSString *)startEngine {
    NSMutableString *status = [NSMutableString string];
    [status appendString:@"Engine Started\n"];
    
    NSString *resourcePath = [[NSBundle mainBundle] pathForResource:@"xmas" ofType:@"xpk"];
    if (resourcePath == nil) {
        [status appendString:@"ERROR: xmas.xpk not found in bundle!"];
        return status;
    }
    
    [status appendFormat:@"Found XPK at: %@\n", [resourcePath lastPathComponent]];
    
    std::string xpkPath = [resourcePath UTF8String];
    
    AssetManager assetMgr;
    if (assetMgr.loadXPK(xpkPath)) {
        [status appendString:@"XPK Loaded Successfully!\n"];
        [status appendString:@"177 files ready in memory."];
    } else {
        [status appendString:@"ERROR: XPK failed to load!"];
    }
    
    return status;
}

@end
